import '../../domain/fx/fx_definition.dart';
import '../../domain/mix/mix_strip.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_entity.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import '../../domain/synth/synth_definition.dart';
import '../../domain/voice/channel_allocation.dart';
import '../../domain/voice/channel_exhausted_exception.dart';
import '../../domain/voice/voice_addresses.dart';
import '../../domain/voice/voice_channel_resolver.dart';
import '../../domain/voice/voice_definition.dart';
import '../../domain/voice/voice_kind.dart';
import '../bridge/fx_chain.dart';
import '../bridge/fx_gateway.dart';
import '../bridge/materialised_fx.dart';
import '../bridge/materialised_synth.dart';
import '../bridge/synth_gateway.dart';
import '../bridge/synth_materialisation.dart';

/// Reports the current voice → channel table and voice → materialised-synth map
/// to whatever drives session flattening + transport connections (the
/// [EngineMidiController]). The [resolver] carries both the internal-voice
/// [ChannelAllocation] and the external-voice channel map; [synths] holds one
/// live [MaterialisedSynth] per internal voice that resolved a synth, keyed by
/// the voice's dotted address (matching `MidiNote.voice`).
typedef VoicesChanged =
    void Function(
      VoiceChannelResolver resolver,
      Map<String, MaterialisedSynth> synths,
    );

/// Reconciles the engine's live **racks** — playable voices and their synths,
/// plus each mix bus's insert-effect chain — against the project registry
/// (design `docs/design/racks-and-voices.md` §3–§5, issue #208).
///
/// The counterpart of [PhiEngine]'s `mix.` channel sync: where that
/// materialises one gateway channel per `mix.` node, this materialises
///
/// - **one engine synth + `Sound` per internal `voice.`** — instantiated from
///   the voice's referenced `synth.` definition on the voice's allocated engine
///   channel and bound to its `mix.` output bus. Two voices sharing one synth
///   definition each get their **own** engine synth (keyed by voice address), so
///   editing that definition re-applies to every dependent voice. A definition
///   edit re-applies **live** (VA panel, FM patch tweak) or **rebuilds** the
///   voice pool (kind / voice-count / bank / sampler-instrument change) per the
///   pure [SynthMaterialisation.needsRematerialise] rule; re-pointing a voice at
///   another synth swaps the sound behind the voice's stable identity, and
///   re-pointing its bus re-binds the existing `Sound`.
/// - **one linked `DspObject` chain per mix bus with `inserts`** — the ordered
///   `fx.` instances the bus lists, materialised as [MaterialisedFx] handles
///   (one per `fx.` entity, keyed by address, re-applied on edit) and placed on
///   the bus in list order through an [FxChain]. Reorder / move follows the
///   registry.
///
/// Everything is keyed by address so a re-sync preserves live engine state — a
/// synth's voice pool, a chain's placement — across an unrelated registry
/// change, exactly as the channel sync preserves a channel's meters. Removed
/// voices dispose their synth (leak-safe, `Sound` before `Synth`); removed
/// effects dispose their handle once the chains no longer borrow it.
///
/// The materialiser owns no transports: it hands the fresh voice table +
/// synth map to [VoicesChanged], and the sessions connect `connectSynth` /
/// `connectMidiOut` by the voices their clips route to (issue #208, in
/// [ClipSession]). Disposal of handles a re-sync retired is **deferred until
/// after** that callback, so a playing session disconnects a retired synth from
/// its transport while the handle is still valid.
class RackMaterialiser {
  RackMaterialiser({
    required SynthGateway synthGateway,
    required FxGateway fxGateway,
    required int? Function(EntityAddress bus) busChannelId,
    required VoicesChanged onVoicesChanged,
  }) : _synthGateway = synthGateway,
       _fxGateway = fxGateway,
       _busChannelId = busChannelId,
       _onVoicesChanged = onVoicesChanged;

  final SynthGateway _synthGateway;
  final FxGateway _fxGateway;

  /// Resolves a `mix.` bus address to its live gateway channel id, or `null`
  /// when it routes to master (or does not exist yet) — the engine's channel map.
  final int? Function(EntityAddress bus) _busChannelId;

  final VoicesChanged _onVoicesChanged;

  /// The internal-voice channel-allocation table, grown/shrunk as voices come
  /// and go (design §3). Stable: a surviving voice keeps its channel across a
  /// re-sync, so its synth's voice banks and its flattened notes stay on the
  /// same engine channel.
  ChannelAllocation _allocation = const ChannelAllocation.empty();

  /// The live engine synth for each internal voice, keyed by voice address.
  final Map<EntityAddress, MaterialisedSynth> _synthByVoice = {};

  /// The `synth.` address each voice's live synth was built from, so a voice
  /// re-pointed at a different definition rebuilds rather than re-applying.
  final Map<EntityAddress, EntityAddress> _synthAddrByVoice = {};

  /// The live effect handle for each `fx.` instance, keyed by its address.
  final Map<EntityAddress, MaterialisedFx> _fxByAddress = {};

  /// The insert chain placed on each mix bus that carries `inserts`, keyed by
  /// bus address.
  final Map<EntityAddress, FxChain> _chainByBus = {};

  /// The handle list last placed on each bus (by identity), so a re-sync
  /// re-places only when the resolved chain actually changed — add / remove /
  /// reorder, or an insert whose kind rebuilt.
  final Map<EntityAddress, List<MaterialisedFx>> _appliedHandles = {};

  /// Reconcile every voice + fx against [registry]. Safe to call on any registry
  /// change: it diffs against the live handles and only touches the engine where
  /// the registry moved.
  void sync(ProjectRegistry registry) {
    // Handles retired this pass, disposed only after [_onVoicesChanged] has let
    // playing sessions disconnect them from their transports (still valid then).
    final toDispose = <MaterialisedSynth>[];
    _syncVoices(registry, toDispose);
    _syncFx(registry);
    for (final handle in toDispose) {
      handle.dispose();
    }
  }

  // ─── voices ───────────────────────────────────────────────────────────────

  void _syncVoices(
    ProjectRegistry registry,
    List<MaterialisedSynth> toDispose,
  ) {
    final internal = <EntityAddress, VoiceDefinition>{};
    final external = <String, int>{};
    _walkNodes(registry, RegistryKinds.voice, (address, node) {
      if (node is! RegistryEntity) return;
      final voice = _voiceOf(node.payload);
      if (voice == null) return;
      if (voice.kind == VoiceKind.external) {
        final channel = voice.channel;
        if (channel != null) external[address.format()] = channel;
      } else {
        internal[address] = voice;
      }
    });

    _reallocate(internal.keys.toSet());

    for (final entry in internal.entries) {
      _materialiseVoice(registry, entry.key, entry.value, toDispose);
    }
    // Voices that vanished or turned external drop their engine synth.
    for (final voiceAddress in _synthByVoice.keys.toList()) {
      if (!internal.containsKey(voiceAddress)) {
        toDispose.add(_synthByVoice.remove(voiceAddress)!);
        _synthAddrByVoice.remove(voiceAddress);
      }
    }

    final synths = <String, MaterialisedSynth>{
      for (final entry in _synthByVoice.entries)
        entry.key.format(): entry.value,
    };
    // Only re-bind (and re-push playing sessions) when the voice table actually
    // moved — a note flattens onto the same channel and a session stays
    // connected to the same synths across an unrelated edit (a clip edit, a live
    // synth-param tweak, an fx change), so those don't force a re-push.
    if (_allocation == _lastAllocation &&
        _sameChannels(external, _lastExternal) &&
        _sameSynths(synths, _lastSynths)) {
      return;
    }
    _lastAllocation = _allocation;
    _lastExternal = external;
    _lastSynths = synths;
    _onVoicesChanged(
      VoiceChannelResolver(
        allocation: _allocation,
        externalChannels: external,
        defaultVoice: VoiceAddresses.defaultVoice,
      ),
      synths,
    );
  }

  /// The voice table last handed to [_onVoicesChanged], so an unrelated re-sync
  /// doesn't re-push playing sessions.
  ChannelAllocation? _lastAllocation;
  Map<String, int> _lastExternal = const {};
  Map<String, MaterialisedSynth> _lastSynths = const {};

  static bool _sameChannels(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _sameSynths(
    Map<String, MaterialisedSynth> a,
    Map<String, MaterialisedSynth> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!identical(b[entry.key], entry.value)) return false;
    }
    return true;
  }

  /// Free channels for gone internal voices and allocate the lowest-free channel
  /// for new ones (in address order, so allocation is deterministic). A voice
  /// past the 16-channel ceiling simply gets no channel — its notes then resolve
  /// to nothing and degrade gracefully (design §3, §6).
  void _reallocate(Set<EntityAddress> desired) {
    for (final voice in _allocation.voices.toList()) {
      if (!desired.contains(voice)) _allocation = _allocation.free(voice);
    }
    final toAllocate = desired.where((v) => !_allocation.contains(v)).toList()
      ..sort((a, b) => a.format().compareTo(b.format()));
    for (final voice in toAllocate) {
      try {
        final (next, _) = _allocation.allocate(voice);
        _allocation = next;
      } on ChannelExhaustedException {
        // Ceiling reached: leave the voice unallocated (channelOf → null).
      }
    }
  }

  void _materialiseVoice(
    ProjectRegistry registry,
    EntityAddress voiceAddress,
    VoiceDefinition voice,
    List<MaterialisedSynth> toDispose,
  ) {
    final channel = _allocation.channelOf(voiceAddress);
    final synthAddress = voice.synth;
    final existing = _synthByVoice[voiceAddress];
    // No channel (ceiling) or no synth definition → this voice can't sound
    // internally; drop any stale handle and leave it silent (still resolvable to
    // its channel once one frees up / the synth appears on a later sync).
    final synthDefinition = synthAddress == null
        ? null
        : _synthDefinitionAt(registry, synthAddress);
    if (channel == null || synthDefinition == null) {
      if (existing != null) {
        toDispose.add(existing);
        _synthByVoice.remove(voiceAddress);
        _synthAddrByVoice.remove(voiceAddress);
      }
      return;
    }
    final busId = _busChannelId(voice.output);

    if (existing == null) {
      _buildVoiceSynth(
        voiceAddress,
        synthAddress!,
        synthDefinition,
        channel,
        busId,
      );
      return;
    }

    final repointed = _synthAddrByVoice[voiceAddress] != synthAddress;
    // A re-point, a channel reassignment, or a rebuild-forcing definition edit
    // all mint a *fresh* engine synth (a new handle), so the session reconnects
    // its transport to the new synth; a live edit or a bus re-point keep the
    // handle and mutate it in place.
    if (repointed ||
        existing.channel != channel ||
        (existing.definition != synthDefinition &&
            SynthMaterialisation.needsRematerialise(
              existing.definition,
              synthDefinition,
            ))) {
      toDispose.add(existing);
      _buildVoiceSynth(
        voiceAddress,
        synthAddress!,
        synthDefinition,
        channel,
        busId,
      );
      return;
    }

    if (existing.definition != synthDefinition) {
      existing.applyDefinition(synthDefinition);
    }
    if (existing.boundBus != busId) existing.bindToBus(busId);
  }

  void _buildVoiceSynth(
    EntityAddress voiceAddress,
    EntityAddress synthAddress,
    SynthDefinition definition,
    int channel,
    int? busId,
  ) {
    final handle = _synthGateway.materialiseSynth(definition, channel: channel);
    handle.bindToBus(busId);
    _synthByVoice[voiceAddress] = handle;
    _synthAddrByVoice[voiceAddress] = synthAddress;
  }

  // ─── fx + insert chains ─────────────────────────────────────────────────────

  void _syncFx(ProjectRegistry registry) {
    // Materialise / re-apply one handle per fx instance.
    final present = <EntityAddress, FxDefinition>{};
    _walkNodes(registry, RegistryKinds.fx, (address, node) {
      if (node is! RegistryEntity) return;
      final fx = _fxOf(node.payload);
      if (fx != null) present[address] = fx;
    });

    final rebuilt = <EntityAddress>{};
    for (final entry in present.entries) {
      final existing = _fxByAddress[entry.key];
      if (existing == null) {
        _fxByAddress[entry.key] = _fxGateway.materialiseFx(entry.value);
      } else if (existing.definition != entry.value) {
        final kindChanged = existing.kind != entry.value.kind;
        existing.applyDefinition(entry.value);
        if (kindChanged) rebuilt.add(entry.key);
      }
    }
    // Retire fx whose entity is gone. Remove from the lookup *now* so the chain
    // reconciliation below excludes them, then dispose after they're unlinked.
    final goneFx = <MaterialisedFx>[];
    for (final address in _fxByAddress.keys.toList()) {
      if (!present.containsKey(address)) {
        goneFx.add(_fxByAddress.remove(address)!);
      }
    }

    _syncChains(registry, rebuilt);

    for (final handle in goneFx) {
      handle.dispose();
    }
  }

  void _syncChains(ProjectRegistry registry, Set<EntityAddress> rebuilt) {
    final busInserts = <EntityAddress, List<EntityAddress>>{};
    _walkNodes(registry, RegistryKinds.mix, (address, node) {
      final inserts = _stripOf(node).inserts;
      if (inserts.isNotEmpty) busInserts[address] = inserts;
    });

    final placed = <EntityAddress>{};
    for (final entry in busInserts.entries) {
      final busId = _busChannelId(entry.key);
      // A bus on master (or not yet materialised) can't host a placed chain.
      if (busId == null) continue;
      final handles = <MaterialisedFx>[
        for (final fxAddress in entry.value)
          if (_fxByAddress[fxAddress] != null) _fxByAddress[fxAddress]!,
      ];
      if (handles.isEmpty) continue;
      placed.add(entry.key);

      var chain = _chainByBus[entry.key];
      if (chain == null || chain.busChannelId != busId) {
        chain?.dispose();
        chain = _fxGateway.createChain(busChannelId: busId);
        _chainByBus[entry.key] = chain;
        chain.setInserts(handles);
        _appliedHandles[entry.key] = handles;
      } else if (!_sameHandles(_appliedHandles[entry.key], handles) ||
          entry.value.any(rebuilt.contains)) {
        chain.setInserts(handles);
        _appliedHandles[entry.key] = handles;
      }
    }

    // Buses that lost every insert (or were removed) detach + drop their chain.
    for (final busAddress in _chainByBus.keys.toList()) {
      if (placed.contains(busAddress)) continue;
      final chain = _chainByBus.remove(busAddress)!;
      chain.setInserts(const []);
      chain.dispose();
      _appliedHandles.remove(busAddress);
    }
  }

  // ─── teardown ───────────────────────────────────────────────────────────────

  /// Dispose every live handle + chain and reset the tables, without touching
  /// the registry — the racks counterpart of the channel teardown, run when the
  /// engine rebinds a different project or stops.
  void teardown() {
    for (final chain in _chainByBus.values) {
      chain.setInserts(const []);
      chain.dispose();
    }
    _chainByBus.clear();
    _appliedHandles.clear();
    for (final fx in _fxByAddress.values) {
      fx.dispose();
    }
    _fxByAddress.clear();
    for (final synth in _synthByVoice.values) {
      synth.dispose();
    }
    _synthByVoice.clear();
    _synthAddrByVoice.clear();
    _allocation = const ChannelAllocation.empty();
    _lastAllocation = null;
    _lastExternal = const {};
    _lastSynths = const {};
  }

  // ─── registry reads ─────────────────────────────────────────────────────────

  /// Visit every node (entity or group) under [kind]'s root, deepest last,
  /// handing each its full [EntityAddress]. Groups recurse so a grouped voice /
  /// synth / fx is reached at its real address.
  void _walkNodes(
    ProjectRegistry registry,
    String kind,
    void Function(EntityAddress address, RegistryNode node) onNode,
  ) {
    void visit(RegistryNode node, EntityAddress address) {
      onNode(address, node);
      if (node is RegistryGroup) {
        for (final child in node.children) {
          visit(child, address.child(child.name));
        }
      }
    }

    for (final child in registry.childrenOfKind(kind)) {
      visit(child, EntityAddress(kind: kind, segments: [child.name]));
    }
  }

  SynthDefinition? _synthDefinitionAt(
    ProjectRegistry registry,
    EntityAddress address,
  ) {
    final payload = registry.entityAt(address)?.payload;
    if (payload is SynthDefinition) return payload;
    if (payload is Map) {
      try {
        return SynthDefinition.fromJson(payload.cast<String, Object?>());
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  VoiceDefinition? _voiceOf(Object? payload) {
    if (payload is VoiceDefinition) return payload;
    if (payload is Map) {
      try {
        return VoiceDefinition.fromJson(payload.cast<String, Object?>());
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  FxDefinition? _fxOf(Object? payload) {
    if (payload is FxDefinition) return payload;
    if (payload is Map) {
      try {
        return FxDefinition.fromJson(payload.cast<String, Object?>());
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// A [MixStrip] from a node's opaque payload — the map form entities/groups
  /// store, a typed strip when built in memory, or a bare default otherwise.
  MixStrip _stripOf(RegistryNode node) {
    final payload = node is RegistryEntity
        ? node.payload
        : node is RegistryGroup
        ? node.payload
        : null;
    if (payload is MixStrip) return payload;
    if (payload is Map) {
      return MixStrip.fromJson(payload.cast<String, Object?>());
    }
    return const MixStrip(voice: 1);
  }

  static bool _sameHandles(List<MaterialisedFx>? a, List<MaterialisedFx> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
