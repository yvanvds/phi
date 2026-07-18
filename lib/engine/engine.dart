import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/midi/custom_transform_registry.dart';
import '../domain/midi/midi_clip_seed.dart';
import '../domain/midi/store/clip_document.dart';
import '../domain/midi/store/midi_transform_codec.dart';
import '../domain/mix/mix_send.dart';
import '../domain/mix/mix_strip.dart';
import '../domain/project/app_settings/audio_settings.dart';
import '../domain/project/app_settings/midi_settings.dart';
import '../domain/project/commands/create_entity_command.dart';
import '../domain/project/commands/create_group_command.dart';
import '../domain/project/commands/move_entity_command.dart';
import '../domain/project/commands/remove_entity_command.dart';
import '../domain/project/commands/reorder_child_command.dart';
import '../domain/project/commands/update_entity_payload_command.dart';
import '../domain/project/commands/update_group_payload_command.dart';
import '../domain/project/entity_address.dart';
import '../domain/project/name_slug.dart';
import '../domain/project/project_command.dart';
import '../domain/project/project_registry.dart';
import '../domain/project/registry_entity.dart';
import '../domain/project/registry_group.dart';
import '../domain/project/registry_kinds.dart';
import '../domain/project/registry_node.dart';
import '../domain/runtime/runtime_variable_registry.dart';
import '../domain/time_domains/time_domain.dart';
import '../domain/time_domains/time_domain_registry.dart';
import 'bridge/audio_device_coordinator.dart';
import 'bridge/audio_device_descriptor.dart';
import 'bridge/audio_device_notice.dart';
import 'bridge/audio_device_state.dart';
import 'bridge/macbear_scene_renderer.dart';
import 'bridge/midi_gateway.dart';
import 'bridge/no_op_registry_mirror.dart';
import 'bridge/patcher_gateway.dart';
import 'bridge/real_midi_gateway.dart';
import 'bridge/real_patcher_gateway.dart';
import 'bridge/real_yse_gateway.dart';
import 'bridge/registry_mirror.dart';
import 'bridge/registry_mirror_binder.dart';
import 'bridge/scene_renderer.dart';
import 'bridge/yse_gateway.dart';
import 'state/clip_registry_publisher.dart';
import 'state/engine_midi_controller.dart';
import 'state/engine_telemetry.dart';
import 'state/mix_tree_node.dart';
import 'state/mixer_channel.dart';
import 'state/patcher_controller.dart';
import 'state/state_machine_controller.dart';

/// High-level façade over the YSE audio engine.
///
/// `PhiEngine` is the only thing the rest of the app talks to about audio.
/// It composes a [YseGateway] (injected for testability), owns the engine
/// lifecycle, and exposes live telemetry as a broadcast stream.
class PhiEngine {
  PhiEngine(
    this._gateway, {
    SceneRenderer? sceneRenderer,
    PatcherGateway? patcherGateway,
    MidiGateway? midiGateway,
    RegistryMirror registryMirror = const NoOpRegistryMirror(),
    Duration telemetryInterval = const Duration(milliseconds: 50),
  }) : _sceneRenderer = sceneRenderer,
       _patcherGateway = patcherGateway,
       _midiGateway = midiGateway,
       _mirrorBinder = RegistryMirrorBinder(registryMirror),
       _telemetryInterval = telemetryInterval {
    // The registry is the source of truth for the channel set (design §8): the
    // engine materialises its `MixerChannel`s from `mix.` entities and re-syncs
    // whenever the tree changes. Until [bindProject] points it at the project's
    // registry it owns a private empty one, so a bare engine (Phase-1 tests)
    // still adds channels — they just live in a registry nobody persists.
    _mixRegistry.addListener(_syncChannelsFromRegistry);
    // The RegistryMirror seam (design §8) follows the same registry, mirroring
    // create / rename / delete / regroup into the engine's Python namespace —
    // a no-op until the live-coding epic swaps in a live mirror.
    _mirrorBinder.bind(_mixRegistry);
  }

  /// Production constructor — wires the real `package:yse` gateway and,
  /// by default, the macbear-backed Scene renderer + the real patcher and
  /// MIDI-output gateways. Tests can inject alternates via the named
  /// parameters.
  factory PhiEngine.production({
    SceneRenderer? sceneRenderer,
    PatcherGateway? patcherGateway,
    MidiGateway? midiGateway,
  }) => PhiEngine(
    RealYseGateway(),
    sceneRenderer: sceneRenderer ?? MacbearSceneRenderer(),
    patcherGateway: patcherGateway ?? RealPatcherGateway(),
    midiGateway: midiGateway ?? RealMidiGateway(),
  );

  final YseGateway _gateway;
  final SceneRenderer? _sceneRenderer;
  final PatcherGateway? _patcherGateway;
  final MidiGateway? _midiGateway;
  final Duration _telemetryInterval;

  /// Coordinates the boot-from-settings and live-switch device rules (design §5,
  /// §9.3) over the gateway. Lazily built so [start] can boot from stored
  /// [AudioSettings]; its notices flow into [_lastAudioNotice].
  late final AudioDeviceCoordinator _audio = AudioDeviceCoordinator(
    _gateway,
    onNotice: (notice) => _lastAudioNotice.value = notice,
  );

  final ValueNotifier<AudioDeviceNotice?> _lastAudioNotice =
      ValueNotifier<AudioDeviceNotice?>(null);

  /// The Scene renderer, if one was wired in. `null` in test setups that
  /// don't exercise the Scene surface.
  SceneRenderer? get sceneRenderer => _sceneRenderer;

  PatcherController? _patcher;

  /// The patcher subsystem. Created lazily on [start]; throws before that
  /// or if `package:yse`'s `Patcher` constructor failed at start (e.g. an
  /// `libyse.dll` without the patcher ABI). Use [patcherOrNull] when the
  /// caller needs to render a fallback.
  PatcherController get patcher {
    final p = _patcher;
    if (p == null) {
      throw StateError('PhiEngine.patcher used before start()');
    }
    return p;
  }

  /// Nullable variant of [patcher] — `null` before [start] *or* when the
  /// patcher subsystem failed to initialise.
  PatcherController? get patcherOrNull => _patcher;

  StateMachineController? _stateMachine;

  /// The state-machine subsystem. Pure Dart — no gateway, no native
  /// counterpart. Created on [start], disposed on [stop]. Throws before
  /// [start]; use [stateMachineOrNull] for the nullable variant.
  StateMachineController get stateMachine {
    final s = _stateMachine;
    if (s == null) {
      throw StateError('PhiEngine.stateMachine used before start()');
    }
    return s;
  }

  /// Nullable variant of [stateMachine] — `null` before [start].
  StateMachineController? get stateMachineOrNull => _stateMachine;

  RuntimeVariableRegistry? _runtimeVariables;

  /// The runtime-variable registry — the store backing the MIDI graph's
  /// `var · name = value` edge guards (issue #78). Pure Dart, like the state
  /// machine; created on [start], disposed on [stop]. Throws before [start];
  /// use [runtimeVariablesOrNull] for the nullable variant.
  RuntimeVariableRegistry get runtimeVariables {
    final r = _runtimeVariables;
    if (r == null) {
      throw StateError('PhiEngine.runtimeVariables used before start()');
    }
    return r;
  }

  /// Nullable variant of [runtimeVariables] — `null` before [start].
  RuntimeVariableRegistry? get runtimeVariablesOrNull => _runtimeVariables;

  EngineMidiController? _midi;

  /// The MIDI subsystem — owns the transform chain, its editor, and the
  /// playback playhead. Created on [start] when a [MidiGateway] was injected;
  /// throws before [start] or when no gateway was wired (tests that don't
  /// exercise MIDI playback). Use [midiOrNull] when the caller needs a
  /// fallback.
  EngineMidiController get midi {
    final m = _midi;
    if (m == null) {
      throw StateError(
        'PhiEngine.midi used before start() or without a gateway',
      );
    }
    return m;
  }

  /// Nullable variant of [midi] — `null` before [start] *or* when no
  /// [MidiGateway] was injected.
  EngineMidiController? get midiOrNull => _midi;

  Timer? _telemetryTimer;
  final StreamController<EngineTelemetry> _telemetry =
      StreamController<EngineTelemetry>.broadcast();
  final ValueNotifier<bool> _testSignal = ValueNotifier<bool>(false);
  final ValueNotifier<double> _masterVolume = ValueNotifier<double>(1);
  final ValueNotifier<bool> _masterMuted = ValueNotifier<bool>(false);

  final MixerChannel _masterChannel = MixerChannel.master();

  /// The mix source of truth (design §8). Defaults to a private empty registry
  /// the engine owns until [bindProject] hands it the project's registry.
  ProjectRegistry _mixRegistry = ProjectRegistry();
  bool _ownsMixRegistry = true;

  /// Forwards the bound registry's lifecycle events to the [RegistryMirror]
  /// seam (design §8). Rebound alongside [_mixRegistry] on every [bindProject].
  final RegistryMirrorBinder _mirrorBinder;

  /// Records structural channel commands (create/remove) for dirty-tracking and
  /// the recovery journal — wired to `ProjectController.recordCommand`. `null`
  /// for a bare engine, which then makes registry edits without journaling them.
  void Function(ProjectCommand)? _recordCommand;

  /// Publishes the live MIDI clip's edits into its `clip.` registry entity
  /// (issue #135). Created when the MIDI subsystem starts, re-bound alongside the
  /// channel registry on every [bindProject]. `null` without a MIDI subsystem.
  ClipRegistryPublisher? _clipPublisher;

  /// The catalogue a persisted `clip.` document's live-coded [CustomTransform]s
  /// re-link against when the engine adopts the clip on [bindProject] (issue
  /// #139). Held as a bare reference — the shell owns it — refreshed on every
  /// bind. `null` decodes customs to passthrough stubs (the default project has
  /// none).
  CustomTransformRegistry? _clipCustomTransforms;

  /// The live channel materialised for each `mix.` node (strip, group bus, or
  /// return), keyed by address so a re-sync preserves channel identity (and its
  /// live volume/peak). Groups are buses (a `mix.` group *is* a channel, design
  /// §3); returns sit outside the tree (design §4).
  final Map<EntityAddress, _MaterialisedChannel> _channelsByAddress = {};

  /// The materialised **non-return** channels (strips + group buses) in tree
  /// pre-order — rebuilt on every sync. Returns are excluded (their own section
  /// lands with the surface work, #170); master is implicit.
  final List<MixerChannel> _userChannels = [];
  final ValueNotifier<List<MixerChannel>> _channels =
      ValueNotifier<List<MixerChannel>>(const []);

  /// The materialised non-return channels shaped as a **tree** (groups carrying
  /// their children), rebuilt on every sync — the grouped rack the Mix surface
  /// renders (design §7). A parallel view of [_channels]; the flat list stays
  /// for the header count and for callers that don't care about nesting.
  final ValueNotifier<List<MixTreeNode>> _mixTree =
      ValueNotifier<List<MixTreeNode>>(const []);

  /// The materialised **return** buses in tree order — the aux buses beside
  /// master (design §4), rebuilt on every sync. Kept apart from [_channels] so
  /// the rack renders strips + groups while the returns section (#170) renders
  /// these.
  final ValueNotifier<List<MixerChannel>> _returns =
      ValueNotifier<List<MixerChannel>>(const []);
  int _voiceCursor = 1;

  /// The (channel, slot) whose send level is mid-drag, or `null` when no send
  /// gesture is live. Mirrors [_volumeGestureChannel] for aux sends (design §4):
  /// while set, [setChannelSendLevel] rams the gateway every tick but defers the
  /// journal write, so a send-level drag emits one `mix.` payload command on
  /// [endSendLevelGesture].
  ({EntityAddress address, int slot})? _sendGesture;

  /// The latest level pushed during the live [_sendGesture], persisted when the
  /// gesture ends.
  double _sendGestureLevel = 1.0;

  /// The channel whose fader is mid-drag, or `null` when no volume gesture is
  /// live. While set, [setChannelVolume] mutates transient state (the live
  /// `MixerChannel` + the gateway) freely but defers the journal write, so a
  /// drag emits **one** `mix.` payload command on [endChannelVolumeGesture]
  /// rather than one per tick (design §6, the gesture-coalescing seam).
  MixerChannel? _volumeGestureChannel;

  bool _started = false;

  /// Whether [start] has been called and [stop] has not.
  bool get isStarted => _started;

  /// Live broadcast of engine telemetry. Listeners receive a new snapshot
  /// every [_telemetryInterval] while the engine is running.
  Stream<EngineTelemetry> get telemetry => _telemetry.stream;

  /// Tick stream that fires on every MIDI input event the engine sees.
  /// Bottom status uses this to flash the MIDI activity dot.
  Stream<void> get midiActivity => _gateway.midiActivity;

  /// Test-signal toggle. Observable so widgets can reflect the armed state.
  ValueListenable<bool> get testSignal => _testSignal;

  /// Master-channel volume in `[0.0, 1.0]`. Observable so faders can bind
  /// directly. Drives the engine's master channel via [setMasterVolume]. Reports
  /// the user-set value even while master mute collapses the *effective* gateway
  /// volume to zero.
  ValueListenable<double> get masterVolume => _masterVolume;

  /// Whether the master channel is muted. Observable so a mute control can bind.
  /// Master is not a registry entity, so this state persists in the project
  /// manifest (design `docs/design/mix.md` §3) — the shell mirrors it through
  /// [SessionState] like the master volume.
  ValueListenable<bool> get masterMuted => _masterMuted;

  /// The master mixer channel. Always present, never destroyed. Mute and
  /// solo on the master are no-ops by design — there is nothing to mix
  /// against it.
  MixerChannel get masterChannel => _masterChannel;

  /// Live list of user channels (master excluded). Fires when channels are
  /// added or removed; per-channel state changes (volume, mute, solo, peak)
  /// fire on the individual [MixerChannel] instead.
  ValueListenable<List<MixerChannel>> get channels => _channels;

  /// The materialised non-return channels as a tree (groups nesting their
  /// children) — the source the Mix surface renders its grouped rack from
  /// (design §7). Fires on every structural re-sync (add / remove / move /
  /// reorder); per-channel state changes fire on the individual [MixerChannel].
  ValueListenable<List<MixTreeNode>> get mixTree => _mixTree;

  /// Live list of return buses (design §4) — the aux buses beside master. Fires
  /// when returns are added or removed; per-return state changes fire on the
  /// individual [MixerChannel].
  ValueListenable<List<MixerChannel>> get returns => _returns;

  /// The registry the engine currently syncs its channels from — its own private
  /// one until [bindProject] rebinds it.
  ProjectRegistry get mixRegistry => _mixRegistry;

  /// Points the engine at the project's [registry] as the channel source of
  /// truth, recording structural channel commands through [recordCommand]
  /// (design §8). Channels materialised from the previous registry are torn down
  /// and rebuilt from [registry] — so opening a project re-creates its saved
  /// strips, and starting a new one clears them. The registry's `clip.` document
  /// is adopted into the live MIDI session (issue #139), so opening a project
  /// also restores its edited clip rather than the boot default. [customTransforms]
  /// is the catalogue that clip's live-coded transforms re-link against. Idempotent
  /// when [registry] is already bound (it only refreshes [recordCommand] and
  /// [customTransforms]).
  void bindProject(
    ProjectRegistry registry, {
    void Function(ProjectCommand)? recordCommand,
    CustomTransformRegistry? customTransforms,
  }) {
    if (identical(registry, _mixRegistry)) {
      _recordCommand = recordCommand;
      _clipCustomTransforms = customTransforms;
      _clipPublisher?.updateRecordCommand(recordCommand);
      return;
    }
    _mixRegistry.removeListener(_syncChannelsFromRegistry);
    if (_ownsMixRegistry) _mixRegistry.dispose();
    _mixRegistry = registry;
    _ownsMixRegistry = false;
    _recordCommand = recordCommand;
    _clipCustomTransforms = customTransforms;
    _mixRegistry.addListener(_syncChannelsFromRegistry);
    _mirrorBinder.bind(_mixRegistry);
    _teardownChannels();
    _syncChannelsFromRegistry();
    _adoptClipAndRebindPublisher();
  }

  /// Adopt the bound registry's `clip.` document into the live MIDI objects, then
  /// (re)bind the clip-edit publisher (issue #139). The publisher is detached
  /// **before** adoption so the in-place mutations that replay the loaded clip
  /// never publish back as spurious edits, and re-bound **after** so it seeds its
  /// de-dupe baseline from the adopted state. No-op without a MIDI subsystem (a
  /// [bindProject] before [start] — [start] runs this once the subsystem exists).
  void _adoptClipAndRebindPublisher() {
    final midi = _midi;
    if (midi == null) return;
    _clipPublisher?.unbind();
    _adoptClipDocument(midi);
    _rebindClipPublisher();
  }

  /// Decode the bound registry's first `clip.` entity into a [ClipDocument] and
  /// adopt it into [midi]'s live clip objects (issue #139). Re-resolves domain
  /// subscriptions against the project's `domain.` entities and re-links custom
  /// transforms against [_clipCustomTransforms], both through the decoding codec.
  /// No-op when the registry carries no clip (or a non-map payload).
  void _adoptClipDocument(EngineMidiController midi) {
    final address = _clipAddressIn(_mixRegistry);
    if (address == null) return;
    final payload = _mixRegistry.entityAt(address)?.payload;
    if (payload is! Map) return;
    final document = ClipDocument.fromJson(
      payload.cast<String, Object?>(),
      transformCodec: MidiTransformCodec(
        customRegistry: _clipCustomTransforms,
        timeDomains: _sessionTimeDomains(),
      ),
    );
    midi.adoptDocument(document);
  }

  /// The session time-domain registry, materialised from the bound registry's
  /// top-level `domain.` entities — what a persisted `DomainSubscriptionTransform`
  /// re-resolves its name against when a clip is adopted (issue #139).
  TimeDomainRegistry _sessionTimeDomains() {
    final domains = <TimeDomain>[];
    for (final node in _mixRegistry.childrenOfKind(RegistryKinds.domain)) {
      if (node is! RegistryEntity) continue;
      final payload = node.payload;
      if (payload is TimeDomain) domains.add(payload);
    }
    return TimeDomainRegistry(domains);
  }

  /// (Re)binds the clip-edit publisher to the bound registry's `clip.` entity so
  /// piano-roll / chain / graph edits persist (issue #135). No-op without a MIDI
  /// subsystem or a clip entity to publish into. Created lazily against the live
  /// [EngineMidiController]'s clip objects, which are stable for its lifetime.
  void _rebindClipPublisher() {
    final midi = _midi;
    if (midi == null) return;
    _clipPublisher ??= ClipRegistryPublisher(
      chain: midi.chain,
      editor: midi.editor,
      graphController: midi.graphController,
    );
    _clipPublisher!.bind(
      registry: _mixRegistry,
      clipAddress: _clipAddressIn(_mixRegistry),
      recordCommand: _recordCommand,
    );
  }

  /// The address of the first top-level `clip.` entity in [registry], or `null`
  /// when none exists — the clip the publisher writes edits back to (the seed
  /// creates exactly one, `clip.phrase_a`).
  EntityAddress? _clipAddressIn(ProjectRegistry registry) {
    for (final node in registry.childrenOfKind(RegistryKinds.clip)) {
      if (node is RegistryEntity) {
        return EntityAddress(kind: RegistryKinds.clip, segments: [node.name]);
      }
    }
    return null;
  }

  /// Initialise the engine, start the update loop, begin emitting telemetry.
  ///
  /// Boots audio from [audioSettings] (design §5): with no stored device it opens
  /// the platform default (`init()`, the pre-settings behaviour and the default
  /// here); with a stored device it `initOffline()`s and opens that device,
  /// falling back to the default with a [lastAudioNotice] when it is missing or
  /// refuses to open — the stored preference is never touched. Engine auto-
  /// reconnect is enabled either way (design §4).
  void start({AudioSettings audioSettings = const AudioSettings()}) {
    if (_started) return;
    _audio.boot(audioSettings);
    // Patcher subsystem is optional — tests that don't inject a
    // PatcherGateway get an engine without a patcher (engine.patcher
    // throws). When wired, the patcher must be created *before*
    // `startUpdateTimer` — otherwise the audio thread can race the
    // constructor. `mainOutputs: 1` matches dart-yse's
    // demo13_patcher.dart and is the only value we've verified
    // end-to-end on the loaded libyse.dll.
    final pg = _patcherGateway;
    if (pg != null) {
      pg.init(mainOutputs: 1);
      _patcher = PatcherController(pg);
    }
    final sm = StateMachineController();
    _stateMachine = sm;
    final rv = RuntimeVariableRegistry();
    _runtimeVariables = rv;
    // MIDI subsystem is optional — tests that don't inject a MidiGateway get
    // an engine without a player (engine.midi throws). When wired, it owns
    // the demo chain + its editor so playback and the piano-roll editor
    // share one source clip.
    final mg = _midiGateway;
    if (mg != null) {
      _midi = EngineMidiController(
        chain: defaultDemoChain(),
        gateway: mg,
        // The state machine drives the graph's live evaluation context, so a
        // graph clip's state-guarded branch re-routes the sounding notes as the
        // live state flips (issue #77).
        stateGraph: sm.graph,
        // The runtime-variable registry drives the graph's other context
        // source, so a `var · mode = lead` branch re-routes as the performance
        // moves the variable (issue #78).
        runtimeVariables: rv,
        // The Scene renderer doubles as the agent sink (issue #37): playing a
        // clip whose chain has an active AgentSpawnTransform populates the 3D
        // Scene. `null` when no renderer is wired — spawning just no-ops.
        agentSink: _sceneRenderer,
      );
    }
    _gateway.startUpdateTimer();
    _sceneRenderer?.init();
    // Note: `mountAsSound` is *not* called here. The patcher is empty at
    // start, and `Sound.fromPatcher` on an empty patcher crashes the audio
    // thread (it reads `~dac` on every callback). The surface mounts after
    // it has seeded a `~dac`.
    _telemetryTimer = Timer.periodic(_telemetryInterval, _emit);
    _started = true;
    _masterVolume.value = _gateway.masterVolume;
    // Materialise any channels the bound registry already holds (e.g. a project
    // restored before start, or a re-start after stop). No-op for the default
    // empty registry.
    _syncChannelsFromRegistry();
    // Now the MIDI subsystem exists, adopt whatever clip the bound registry
    // carries and wire the clip-edit publisher (bindProject may have run before
    // start). A no-op for the default empty registry.
    _adoptClipAndRebindPublisher();
  }

  /// Stop telemetry, close the engine.
  void stop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    if (_started) {
      _patcher?.dispose();
      _patcher = null;
      _patcherGateway?.dispose();
      _stateMachine?.dispose();
      _stateMachine = null;
      _runtimeVariables?.dispose();
      _runtimeVariables = null;
      _clipPublisher?.unbind();
      _clipPublisher = null;
      _midi?.dispose();
      _midi = null;
      _teardownChannels();
      _gateway.close();
      _sceneRenderer?.dispose();
      _started = false;
    }
    _testSignal.value = false;
  }

  /// Tears down every materialised channel (disposing its `MixerChannel` and
  /// destroying its gateway channel while the engine is running), leaving the
  /// registry untouched. A later [_syncChannelsFromRegistry] rebuilds from the
  /// tree.
  void _teardownChannels() {
    _volumeGestureChannel = null;
    _sendGesture = null;
    for (final mc in _channelsByAddress.values) {
      if (_started) _gateway.destroyChannel(mc.channel.id);
      mc.channel.dispose();
    }
    _channelsByAddress.clear();
    _userChannels.clear();
    _channels.value = const [];
    _mixTree.value = const [];
    _returns.value = const [];
  }

  /// Tree-aware reconciliation of the materialised channels against the `mix.`
  /// tree in [_mixRegistry] (design §8): groups (buses) are materialised **before
  /// their children** so a child always has a parent to hang from, returns are
  /// created outside the tree, nodes whose entity is gone are destroyed, a node
  /// that merely moved (a regroup — same leaf name, new parent) is **re-parented
  /// with `moveChannel`** rather than torn down, and — in a **second pass**, once
  /// every channel exists — aux sends are wired to their return buses. Channel
  /// identity stays keyed by address, so a persisting node keeps its live
  /// volume/mute/solo/peak (and mid-gesture state) across an unrelated re-sync.
  /// No-op before [start] (no gateway to create channels on).
  void _syncChannelsFromRegistry() {
    if (!_started) return;
    final desired = _walkMixTree();
    final desiredAddresses = {for (final node in desired) node.address};

    // A move changes a node's address (its address *is* its tree path, so a
    // regroup shifts it), which reads here as one address gone and another
    // appeared. Correlate a gone address to an appeared one by **leaf name** — a
    // pure reparent keeps the name — so the gateway channel is `moveChannel`d
    // rather than destroyed and rebuilt, preserving its live meters and sends.
    // Ambiguous names (present more than once on either side) fall back to a
    // destroy + create, which is correct, just a brief dropout.
    final gone = _channelsByAddress.keys
        .where((a) => !desiredAddresses.contains(a))
        .toList();
    final appeared = desired
        .where((node) => !_channelsByAddress.containsKey(node.address))
        .map((node) => node.address)
        .toList();
    final correlated = _correlateMoves(gone, appeared);

    // Rekey correlated survivors to their new address (identity preserved).
    for (final entry in correlated.entries) {
      _channelsByAddress[entry.key] = _channelsByAddress.remove(entry.value)!;
    }
    // Destroy the genuinely removed nodes.
    for (final address in gone) {
      if (correlated.containsValue(address)) continue;
      final mc = _channelsByAddress.remove(address)!;
      _gateway.destroyChannel(mc.channel.id);
      mc.channel.dispose();
    }

    // Materialise / re-parent in tree pre-order (parents precede children).
    for (final node in desired) {
      final parentId = node.parentAddress == null
          ? null
          : _channelsByAddress[node.parentAddress]?.channel.id;
      final existing = _channelsByAddress[node.address];
      if (existing == null) {
        _channelsByAddress[node.address] = _createChannel(node, parentId);
      } else if (!existing.isReturn && existing.parentId != parentId) {
        // A re-parented survivor (or one whose parent bus was rebuilt with a
        // new id): move it under the current parent.
        _gateway.moveChannel(existing.channel.id, parentId);
        existing.parentId = parentId;
      }
    }

    _userChannels
      ..clear()
      ..addAll([
        for (final node in desired)
          if (!node.isReturn) _channelsByAddress[node.address]!.channel,
      ]);
    _channels.value = List<MixerChannel>.unmodifiable(_userChannels);
    _returns.value = List<MixerChannel>.unmodifiable([
      for (final node in desired)
        if (node.isReturn) _channelsByAddress[node.address]!.channel,
    ]);

    // Second pass: every channel exists now, so aux sends can be wired to their
    // return targets (design §8 — "targets must exist first").
    for (final node in desired) {
      _reconcileSends(node);
    }

    _rebuildMixTree(desired);
    _recomputeEffectiveVolumes();
  }

  /// Rebuilds the [mixTree] view from the flat, pre-ordered [desired] nodes —
  /// nesting each non-return node under its parent so the surface renders groups
  /// as framed sections (design §7). Returns are excluded (they surface through
  /// [returns]); pre-order guarantees a parent is built before its children.
  void _rebuildMixTree(List<_MixNode> desired) {
    final builders = <EntityAddress, _MixTreeBuilder>{};
    final roots = <_MixTreeBuilder>[];
    for (final node in desired) {
      if (node.isReturn) continue;
      final builder = _MixTreeBuilder(
        _channelsByAddress[node.address]!.channel,
        node.address,
        node.isGroup,
      );
      builders[node.address] = builder;
      final parent = node.parentAddress == null
          ? null
          : builders[node.parentAddress];
      if (parent == null) {
        roots.add(builder);
      } else {
        parent.children.add(builder);
      }
    }
    _mixTree.value = List<MixTreeNode>.unmodifiable(
      roots.map((b) => b.freeze()),
    );
  }

  /// Creates the gateway channel + `MixerChannel` for a freshly-appeared [node],
  /// adopting its persisted live mix state (issue #136). A return goes through
  /// [YseGateway.createReturnChannel] with enough send slots for its payload
  /// (design §10 decision 4); a strip or group bus is an ordinary tree channel
  /// under [parentId] (`null` = master).
  _MaterialisedChannel _createChannel(_MixNode node, int? parentId) {
    final name = node.address.name;
    final int id;
    if (node.isReturn) {
      id = _gateway.createReturnChannel(
        name,
        sendSlots: node.strip.sends.length > 4 ? node.strip.sends.length : 4,
      );
    } else {
      id = _gateway.createChannel(name, parentId: parentId);
    }
    final channel =
        MixerChannel.user(id: id, name: name, voice: node.strip.voice)
          ..applyVolume(node.strip.volume)
          ..applyMuted(node.strip.muted)
          ..applySoloed(node.strip.soloed);
    return _MaterialisedChannel(
      channel,
      isReturn: node.isReturn,
      parentId: parentId,
    );
  }

  /// old → new address for every gone/appeared pair that shares a **unique** leaf
  /// name — a node reparented within the tree. Returns `{newAddress: oldAddress}`.
  Map<EntityAddress, EntityAddress> _correlateMoves(
    List<EntityAddress> gone,
    List<EntityAddress> appeared,
  ) {
    List<EntityAddress> uniqueByName(List<EntityAddress> addresses) {
      final counts = <String, int>{};
      for (final a in addresses) {
        counts[a.name] = (counts[a.name] ?? 0) + 1;
      }
      return [
        for (final a in addresses)
          if (counts[a.name] == 1) a,
      ];
    }

    final goneByName = {for (final a in uniqueByName(gone)) a.name: a};
    final result = <EntityAddress, EntityAddress>{};
    for (final newAddress in uniqueByName(appeared)) {
      final old = goneByName[newAddress.name];
      if (old != null) result[newAddress] = old;
    }
    return result;
  }

  /// Walks the `mix.` tree depth-first (pre-order, so a group precedes its
  /// children) into a flat list of nodes carrying their parent address. A
  /// top-level entity with `return: true` is a return bus (outside the tree, so
  /// no parent, no children); every other node is a strip or a group bus.
  List<_MixNode> _walkMixTree() {
    final nodes = <_MixNode>[];
    void visit(
      RegistryNode node,
      EntityAddress address,
      EntityAddress? parent,
    ) {
      if (node is RegistryGroup) {
        // A `mix.` group *is* a bus (design §3). A payload-less structural
        // ancestor still becomes a bus so its children have a parent.
        nodes.add(
          _MixNode(address, parent, false, true, _stripOf(node.payload)),
        );
        for (final child in node.children) {
          visit(child, address.child(child.name), address);
        }
      } else if (node is RegistryEntity) {
        final strip = _stripOf(node.payload);
        final isReturn = strip.isReturn && address.isTopLevel;
        nodes.add(
          _MixNode(address, isReturn ? null : parent, isReturn, false, strip),
        );
      }
    }

    for (final child in _mixRegistry.childrenOfKind(RegistryKinds.mix)) {
      visit(
        child,
        EntityAddress(kind: RegistryKinds.mix, segments: [child.name]),
        null,
      );
    }
    return nodes;
  }

  /// A [MixStrip] from a node's opaque [payload] — the map form entities/groups
  /// store, falling back to a bare default for a payload-less structural group.
  MixStrip _stripOf(Object? payload) => payload is Map
      ? MixStrip.fromJson(payload.cast<String, Object?>())
      : const MixStrip(voice: 1);

  /// Wires [node]'s aux sends to their return buses, reconciling against what is
  /// already applied so an unchanged send is not re-sent (design §4): a new or
  /// re-targeted slot goes through [YseGateway.setSend], a level-only change
  /// through the ramped [YseGateway.setSendLevel], and a dropped slot through
  /// [YseGateway.clearSend]. A send whose target is missing or is not a return is
  /// skipped (the gateway would reject it anyway). The slot mid-gesture is left
  /// untouched so a live send-level drag is never stomped by an unrelated sync.
  void _reconcileSends(_MixNode node) {
    final mc = _channelsByAddress[node.address]!;
    final applied = mc.appliedSends;
    final sends = node.strip.sends;

    // Drop applied slots the payload no longer carries.
    for (final slot in applied.keys.toList()) {
      if (slot >= sends.length) {
        _gateway.clearSend(mc.channel.id, slot);
        applied.remove(slot);
      }
    }

    for (var slot = 0; slot < sends.length; slot++) {
      if (_sendGesture == (address: node.address, slot: slot)) continue;
      final send = sends[slot];
      final target = _channelsByAddress[send.to];
      if (target == null || !target.isReturn) {
        if (applied.remove(slot) != null) {
          _gateway.clearSend(mc.channel.id, slot);
        }
        continue;
      }
      final returnId = target.channel.id;
      final prev = applied[slot];
      if (prev == null ||
          prev.returnId != returnId ||
          prev.preFader != send.preFader) {
        _gateway.setSend(
          mc.channel.id,
          slot,
          returnId,
          send.level,
          send.preFader,
        );
        applied[slot] = _AppliedSend(returnId, send.level, send.preFader);
      } else if (prev.level != send.level) {
        _gateway.setSendLevel(mc.channel.id, slot, send.level);
        prev.level = send.level;
      }
    }
  }

  /// Turn the engine's built-in audio test signal on or off.
  void setTestSignal({required bool on}) {
    if (!_started) return;
    _gateway.audioTest = on;
    _testSignal.value = on;
  }

  /// The audio settings describing the device currently open — what a failed
  /// live switch reverts to. Reads the coordinator's live state, not the stored
  /// preference (they can differ after a boot fallback, design §5).
  AudioSettings get activeAudioSettings => _audio.current;

  /// The audio devices the engine can currently see, as pure FFI-free
  /// [AudioDeviceDescriptor]s (design §4) — the list the settings dialog's AUDIO
  /// section builds its output-device / rate / buffer pickers from. Empty before
  /// [start] (no device surface yet); the shell never touches the gateway, so
  /// this façade method is the only way above the bridge to enumerate devices.
  List<AudioDeviceDescriptor> audioDevices() =>
      _started ? _gateway.audioDevices() : const [];

  /// The live state of whichever device is open — active sample rate, buffer, and
  /// output latency (design §4) — the settings dialog's read-back line. Reads the
  /// device, not the stored settings (they can differ). [AudioDeviceState.none]
  /// before [start] or when no device is open.
  AudioDeviceState activeAudioState() =>
      _started ? _gateway.activeAudioState() : AudioDeviceState.none;

  /// The most recent non-blocking audio notice — a boot fallback or a reverted
  /// live switch (design §5, §9.3) — or `null` when none has been raised.
  /// Retained (not a stream) so a consumer that binds after boot still sees a
  /// launch-time fallback.
  ValueListenable<AudioDeviceNotice?> get lastAudioNotice => _lastAudioNotice;

  /// Applies a live audio-device change (design §5 "Live change", §9.3): swaps to
  /// [desired], reverting to the previous working device (with a
  /// [lastAudioNotice]) when it is missing or refuses to open. Returns `true` on
  /// success — or a no-op when [desired] is already open — so the caller persists
  /// the stored choice only when it does. Returns `false` (a no-op) before
  /// [start].
  bool switchAudioDevice(AudioSettings desired) {
    if (!_started) return false;
    return _audio.switchTo(desired);
  }

  // ─── MIDI ports (design §5, §6) ──────────────────────────────────────────
  //
  // The settings dialog's MIDI section reaches the hardware only through these
  // façade methods — the shell never touches the MIDI gateway directly. Output
  // and input ports are addressed by **name**; a stored name resolves to the
  // current device index each time a port is opened, so a replug keeps working.

  /// The MIDI output ports the engine can currently see, by name — the list the
  /// settings dialog's output-port picker is built from. Empty when no MIDI
  /// gateway was wired (tests that don't exercise MIDI).
  List<String> midiOutputPorts() {
    final mg = _midiGateway;
    if (mg == null) return const [];
    return [
      for (var i = 0; i < mg.outputDeviceCount; i++) mg.outputDeviceName(i),
    ];
  }

  /// The MIDI input ports the engine can currently see, by name — the settings
  /// dialog's input checklist. Empty when no MIDI gateway was wired.
  List<String> midiInputPorts() => _midiGateway?.inputDeviceNames() ?? const [];

  /// The names of the MIDI input ports currently open. Empty when none are open
  /// or no MIDI gateway was wired.
  List<String> openMidiInputs() => _midiGateway?.openInputNames ?? const [];

  /// The chosen MIDI output port's name, or `null` for the default (first port).
  /// `null` before [start] or when no MIDI gateway was wired.
  String? get midiOutputPort => _midi?.outputPortName;

  /// Broadcast of the **port name** on every MIDI message received on an open
  /// input port — the settings dialog flashes that port's activity dot (design
  /// §6). An empty stream when no MIDI gateway was wired.
  Stream<String> get midiInputActivity =>
      _midiGateway?.inputActivity ?? const Stream<String>.empty();

  /// Applies [settings] to the MIDI subsystem (design §5): sets the output port
  /// by name (resolved to an index at open time, so a replug keeps working) and
  /// opens exactly the enabled input ports, closing any others. The output port
  /// no-ops before [start] (no player yet); input ports open through the gateway
  /// regardless. Nothing is *routed* from the inputs yet — this only remembers
  /// and opens the hardware (design §8).
  void applyMidiSettings(MidiSettings settings) {
    _midi?.outputPortName = settings.outputPort;
    _midiGateway?.openInputs(settings.inputPorts);
  }

  // ─── Diagnostics (design §6) ─────────────────────────────────────────────

  /// The libYSE library version string — a read-only diagnostics fact.
  String get engineVersion => _gateway.engineVersion;

  /// The resolved engine-library path (`YSE_DLL_PATH`), or `null` when unset —
  /// a read-only diagnostics fact.
  String? get engineLibraryPath => _gateway.libraryPath;

  /// The count of audio callbacks that failed to complete on time — the
  /// diagnostics "drop counter". `0` before [start].
  int get missedCallbacks => _started ? _gateway.missedCallbacks : 0;

  /// Set the master-channel volume. Clamped to `[0.0, 1.0]`. No-op before
  /// [start]. When master mute is engaged the *effective* gateway volume stays
  /// zero, but the user value is still remembered (and reported by
  /// [masterVolume]).
  void setMasterVolume(double value) {
    if (!_started) return;
    final clamped = value.clamp(0.0, 1.0);
    _masterVolume.value = clamped;
    _masterChannel.applyVolume(clamped);
    _pushMasterEffective();
  }

  /// Mute or unmute the master channel — collapses the effective gateway volume
  /// to zero while remembering the user volume. No-op before [start]. Persists
  /// through the manifest like [setMasterVolume].
  void setMasterMuted({required bool muted}) {
    if (!_started) return;
    _masterMuted.value = muted;
    _masterChannel.applyMuted(muted);
    _pushMasterEffective();
  }

  /// Pushes the master channel's *effective* volume (zero while muted) to the
  /// gateway — the master counterpart of the per-channel mute collapse.
  void _pushMasterEffective() {
    _gateway.masterVolume = _masterMuted.value ? 0.0 : _masterVolume.value;
  }

  /// Adds a user channel by creating a `mix.` entity in the registry — the
  /// registry is the source of truth, so the [MixerChannel] is materialised by
  /// the ensuing sync rather than appended directly (design §8). Picks the next
  /// voice slot in `[1, 6]`, wrapping, and slugs [name] into a unique address.
  /// The create is recorded for dirty-tracking + journaling. No-op before
  /// [start]. Returns the materialised [MixerChannel].
  MixerChannel addChannel({String? name}) {
    if (!_started) {
      throw StateError('PhiEngine.addChannel called before start()');
    }
    final voice = _voiceCursor;
    _voiceCursor = (_voiceCursor % 6) + 1;
    final resolvedName = name ?? 'ch ${_userChannels.length + 1}';
    final address = _uniqueMixAddress(resolvedName);
    final command = CreateEntityCommand(
      _mixRegistry,
      address,
      payload: MixStrip(voice: voice).toJson(),
    );
    command.apply(); // notifies → _syncChannelsFromRegistry materialises it
    _recordCommand?.call(command);
    return _channelsByAddress[address]!.channel;
  }

  /// Adds a **group bus** — a `mix.` group carrying a strip payload, so it has a
  /// fader of its own (design §3). Created top-level through [CreateGroupCommand];
  /// child strips join it by being dragged in ([moveChannelToGroup]). Picks the
  /// next voice slot and slugs [name] into a unique address, recording the create
  /// for dirty-tracking + journaling. Returns the materialised group [MixerChannel].
  MixerChannel addGroup({String? name}) {
    if (!_started) {
      throw StateError('PhiEngine.addGroup called before start()');
    }
    final voice = _voiceCursor;
    _voiceCursor = (_voiceCursor % 6) + 1;
    final address = _uniqueMixAddress(name ?? 'group');
    final command = CreateGroupCommand(
      _mixRegistry,
      address,
      payload: MixStrip(voice: voice).toJson(),
    );
    command.apply(); // notifies → sync materialises the group bus
    _recordCommand?.call(command);
    return _channelsByAddress[address]!.channel;
  }

  /// Adds a **return bus** — a top-level `mix.` entity flagged `return: true`
  /// (design §4), so it lands outside the tree in [returns] rather than the rack.
  /// Picks the next voice slot and slugs [name] into a unique address, recording
  /// the create. Returns the materialised return [MixerChannel].
  MixerChannel addReturn({String? name}) {
    if (!_started) {
      throw StateError('PhiEngine.addReturn called before start()');
    }
    final voice = _voiceCursor;
    _voiceCursor = (_voiceCursor % 6) + 1;
    final address = _uniqueMixAddress(name ?? 'return');
    final command = CreateEntityCommand(
      _mixRegistry,
      address,
      payload: MixStrip(voice: voice, isReturn: true).toJson(),
    );
    command.apply(); // notifies → sync materialises the return bus
    _recordCommand?.call(command);
    return _channelsByAddress[address]!.channel;
  }

  /// Re-parents [channel] under the group bus at [group] (appended among its
  /// children), or back to top level when [group] is `null` — the drag-into /
  /// drag-out-of-a-group gesture (design §7). A registry **move** rewrites the
  /// address to follow the tree (rename = refactor), and the ensuing sync
  /// `moveChannel`s the gateway channel, preserving its live meters (design §8).
  /// No-op for the master, a stale handle, a channel already directly under
  /// [group], or a group dropped into its own subtree. Records the move.
  void moveChannelToGroup(MixerChannel channel, EntityAddress? group) {
    if (!_started || channel.isMaster) return;
    final from = _addressOf(channel);
    if (from == null) return;
    final parentSegments = group?.segments ?? const <String>[];
    if (_sameSegments(from.groupPath, parentSegments)) return; // already there
    // Never drop a group into itself or its own subtree (the registry throws).
    if (group != null && (group == from || group.isDescendantOf(from))) return;
    final to = _uniqueMixAddressUnder(parentSegments, from.name);
    final command = MoveEntityCommand(_mixRegistry, from, to);
    command.apply(); // notifies → sync re-parents the gateway channel
    _recordCommand?.call(command);
  }

  /// Reorders [channel] to sit immediately before [before] among their shared
  /// siblings — the drag-to-reorder-within-a-section gesture (design §7). No-op
  /// unless the two currently share a parent (a cross-group drop is a
  /// [moveChannelToGroup] instead). The new order persists through the group's
  /// `_group.json`. Records the reorder.
  void moveChannelBefore(MixerChannel channel, MixerChannel before) {
    if (!_started) return;
    final from = _addressOf(channel);
    final target = _addressOf(before);
    if (from == null || target == null || from == target) return;
    if (from.parent != target.parent) return; // reorder is within one parent
    final group = from.parent; // null → the kind root (top level)
    final siblings = group == null
        ? _mixRegistry.childrenOfKind(RegistryKinds.mix)
        : _mixRegistry.childrenOfGroup(group);
    final names = siblings.map((n) => n.name).toList();
    final fromIndex = names.indexOf(from.name);
    final targetIndex = names.indexOf(target.name);
    if (fromIndex < 0 || targetIndex < 0) return;
    // "Immediately before target": removing the moved child first shifts an
    // earlier target left by one, so land at targetIndex-1 in that case.
    final toIndex = fromIndex < targetIndex ? targetIndex - 1 : targetIndex;
    if (toIndex == fromIndex) return;
    final command = ReorderChildCommand(
      _mixRegistry,
      kind: RegistryKinds.mix,
      group: group,
      childName: from.name,
      fromIndex: fromIndex,
      toIndex: toIndex,
    );
    command.apply(); // notifies → sync rebuilds the tree in the new order
    _recordCommand?.call(command);
  }

  /// Removes a user channel by removing its `mix.` entity; the ensuing sync
  /// destroys the gateway channel and disposes the [MixerChannel]. No-op for the
  /// master channel or an instance the engine no longer holds. The removal is
  /// recorded for dirty-tracking + journaling.
  void removeChannel(MixerChannel channel) {
    if (channel.isMaster) return;
    final address = _addressOf(channel);
    if (address == null) return;
    final command = RemoveEntityCommand(_mixRegistry, address);
    command.apply(); // notifies → _syncChannelsFromRegistry tears it down
    _recordCommand?.call(command);
  }

  /// Renames a user channel by **moving** its `mix.` entity to the slug of the
  /// new name, so the address follows the name — "rename = refactor" (design §4),
  /// which rewrites any back-references to the channel as one journaled command.
  /// Since the one-name re-alignment (issue #166) a strip has no separate display
  /// name — the channel is named by its address leaf — so a rename is purely that
  /// move: the live volume/mute/solo/sends ride the payload and survive it. No-op
  /// for the master channel, an instance the engine no longer holds, a blank
  /// name, or a name whose slug is unchanged (the name already *is* the slug, so
  /// there is nothing to rename).
  void renameChannel(MixerChannel channel, String name) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    final address = _addressOf(channel);
    if (address == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final newSlug = NameSlug.of(trimmed, fallback: 'channel');
    if (newSlug == address.name) return; // the name *is* the slug — no change
    final newAddress = _uniqueMixAddress(trimmed);
    final move = MoveEntityCommand(_mixRegistry, address, newAddress);
    move.apply(); // notifies → sync rematerialises the channel at the new slug
    _recordCommand?.call(move);
  }

  /// The registry address of a materialised [channel], or `null` when the engine
  /// no longer holds it.
  EntityAddress? _addressOf(MixerChannel channel) {
    for (final entry in _channelsByAddress.entries) {
      if (identical(entry.value.channel, channel)) return entry.key;
    }
    return null;
  }

  /// Whether the engine currently materialises [channel] (a strip, group bus, or
  /// return) — the guard for the per-channel mutators. Master and stale handles
  /// are excluded.
  bool _holds(MixerChannel channel) => _addressOf(channel) != null;

  /// A free top-level `mix.` address for a channel named [displayName] — the
  /// slug of the name, suffixed `_2`, `_3`, … until it is unused.
  EntityAddress _uniqueMixAddress(String displayName) {
    final base = NameSlug.of(displayName, fallback: 'channel');
    var segment = base;
    var n = 2;
    while (_mixRegistry.contains(
      EntityAddress(kind: RegistryKinds.mix, segments: [segment]),
    )) {
      segment = '${base}_$n';
      n++;
    }
    return EntityAddress(kind: RegistryKinds.mix, segments: [segment]);
  }

  /// A free `mix.` address for [leaf] directly under [parentSegments] (empty =
  /// top level) — the leaf itself, else suffixed `_2`, `_3`, … until unused. The
  /// destination a drag-into-a-group move targets.
  EntityAddress _uniqueMixAddressUnder(
    List<String> parentSegments,
    String leaf,
  ) {
    var segment = leaf;
    var n = 2;
    while (_mixRegistry.contains(
      EntityAddress(
        kind: RegistryKinds.mix,
        segments: [...parentSegments, segment],
      ),
    )) {
      segment = '${leaf}_$n';
      n++;
    }
    return EntityAddress(
      kind: RegistryKinds.mix,
      segments: [...parentSegments, segment],
    );
  }

  static bool _sameSegments(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Set a channel's user-facing volume. Clamped to `[0.0, 1.0]`. Routes
  /// through [setMasterVolume] for the master channel; for user channels
  /// the effective gateway volume also respects mute and solo.
  void setChannelVolume(MixerChannel channel, double value) {
    if (!_started) return;
    final clamped = value.clamp(0.0, 1.0);
    if (channel.isMaster) {
      setMasterVolume(clamped);
      return;
    }
    if (!_holds(channel)) return;
    channel.applyVolume(clamped);
    _recomputeEffectiveVolumes();
    // Persist the new fader value — unless a drag gesture is live for this
    // channel, in which case the write is coalesced into the single command
    // [endChannelVolumeGesture] emits (design §6). A tap or a programmatic set
    // has no gesture, so it persists immediately.
    if (!identical(_volumeGestureChannel, channel)) {
      _persistChannelState(channel);
    }
  }

  /// Marks the start of a fader drag on [channel]: subsequent
  /// [setChannelVolume] calls mutate transient state without journaling, so the
  /// whole drag coalesces into one `mix.` payload command on
  /// [endChannelVolumeGesture]. No-op for the master strip (not a persisted
  /// `mix.` entity) or a channel the engine no longer holds. If a previous
  /// gesture on another channel was never ended, it is flushed first so no edit
  /// is lost.
  void beginChannelVolumeGesture(MixerChannel channel) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    final pending = _volumeGestureChannel;
    if (pending != null && !identical(pending, channel)) {
      _volumeGestureChannel = null;
      _persistChannelState(pending);
    }
    _volumeGestureChannel = channel;
  }

  /// Marks the end of a fader drag on [channel] and flushes the coalesced fader
  /// value as one journaled `mix.` payload command. No-op when no gesture is
  /// live for [channel].
  void endChannelVolumeGesture(MixerChannel channel) {
    if (!identical(_volumeGestureChannel, channel)) return;
    _volumeGestureChannel = null;
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    _persistChannelState(channel);
  }

  /// Mute or unmute a channel (strip or group bus). Master mute is set through
  /// [setMasterMuted]; muting a group silences its whole subtree (design §5).
  /// Triggers a tree-wide solo/mute re-evaluation. Discrete, so it persists
  /// immediately (issue #136).
  void setChannelMuted(MixerChannel channel, {required bool muted}) {
    if (!_started || channel.isMaster) return;
    if (!_holds(channel)) return;
    channel.applyMuted(muted);
    _recomputeEffectiveVolumes();
    _persistChannelState(channel);
  }

  /// Toggle a channel's solo flag. Solo audibility follows the tree (design §5):
  /// the soloed nodes, their descendants, and their ancestors stay open; every
  /// other tree node is silenced until solo clears; returns are exempt. Mute wins
  /// on the path, so a soloed leaf inside a muted group stays silent.
  void setChannelSoloed(MixerChannel channel, {required bool soloed}) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    channel.applySoloed(soloed);
    _recomputeEffectiveVolumes();
    // Only the toggled channel's own soloed flag is persisted state; the effect
    // on other channels is derived (effective volume), not saved.
    _persistChannelState(channel);
  }

  /// Recomputes and pushes every materialised channel's **effective** gateway
  /// volume from the live solo/mute state, walking the tree (design §5):
  ///
  /// - **Mute wins on the path** — a node with a muted ancestor (or itself muted)
  ///   is silent, so a soloed leaf inside a muted group stays silent.
  /// - **Solo** (when any tree node is soloed) keeps audible only the soloed
  ///   nodes, their descendants, and their ancestors (the path to master); every
  ///   other tree node is silenced.
  /// - **Returns are exempt from solo** (design §5 / §10 decision 3) — a return's
  ///   effective volume follows its own mute alone.
  ///
  /// The address *is* the tree path, so ancestry is read straight off addresses.
  void _recomputeEffectiveVolumes() {
    final tree = {
      for (final entry in _channelsByAddress.entries)
        if (!entry.value.isReturn) entry.key: entry.value.channel,
    };
    final anySoloed = tree.values.any((c) => c.soloed);

    // The audible set under solo: every soloed node with its descendants and its
    // ancestors.
    final soloAudible = <EntityAddress>{};
    if (anySoloed) {
      for (final soloed in tree.entries.where((e) => e.value.soloed)) {
        soloAudible.add(soloed.key);
        for (final other in tree.keys) {
          if (other.isDescendantOf(soloed.key) ||
              soloed.key.isDescendantOf(other)) {
            soloAudible.add(other);
          }
        }
      }
    }

    for (final entry in tree.entries) {
      final address = entry.key;
      final channel = entry.value;
      final mutedOnPath =
          channel.muted ||
          tree.entries.any(
            (a) =>
                a.key != address &&
                address.isDescendantOf(a.key) &&
                a.value.muted,
          );
      final audible = mutedOnPath
          ? false
          : (anySoloed ? soloAudible.contains(address) : true);
      _gateway.setChannelVolume(channel.id, audible ? channel.volume : 0.0);
    }

    // Returns sit outside the tree and are exempt from solo — mute alone.
    for (final mc in _channelsByAddress.values.where((mc) => mc.isReturn)) {
      _gateway.setChannelVolume(
        mc.channel.id,
        mc.channel.muted ? 0.0 : mc.channel.volume,
      );
    }
  }

  // ─── Aux sends (design §4) ───────────────────────────────────────────────

  /// Adds or replaces the aux send in [slot] of [channel], routing it to the
  /// [returnBus] at [level] (post-fader unless [preFader]). The edit lands in the
  /// strip payload and the ensuing sync wires the gateway (the second-pass send
  /// wiring), so it persists and journals like any payload change. No-op unless
  /// [returnBus] is a materialised return (the only legal target, design §4) and
  /// [channel] is a materialised strip/bus.
  void setChannelSend(
    MixerChannel channel,
    int slot, {
    required MixerChannel returnBus,
    double level = 1.0,
    bool preFader = false,
  }) {
    if (!_started || slot < 0) return;
    final address = _addressOf(channel);
    final returnAddress = _addressOf(returnBus);
    if (address == null || returnAddress == null) return;
    if (!(_channelsByAddress[returnAddress]?.isReturn ?? false)) return;
    final strip = _storedStrip(address);
    if (strip == null) return;
    final send = MixSend(
      to: returnAddress,
      level: level.clamp(0.0, 1.0),
      preFader: preFader,
    );
    _persistSends(address, _withSendAt(strip.sends, slot, send));
  }

  /// Detaches the send in [slot] of [channel] (design §4) — a payload edit the
  /// sync clears at the gateway. No-op when the slot is unset.
  void clearChannelSend(MixerChannel channel, int slot) {
    if (!_started || slot < 0) return;
    final address = _addressOf(channel);
    if (address == null) return;
    final strip = _storedStrip(address);
    if (strip == null || slot >= strip.sends.length) return;
    _persistSends(address, _withSendRemovedAt(strip.sends, slot));
  }

  /// Set the level of the send in [slot] of [channel], ramped and click-free
  /// (design §4) — safe to write every control tick during a drag. Coalesces the
  /// journal write like a fader gesture: while a [beginSendLevelGesture] is live
  /// for this slot the level rams the gateway but the payload is written once, on
  /// [endSendLevelGesture]; a set with no gesture persists immediately.
  void setChannelSendLevel(MixerChannel channel, int slot, double level) {
    if (!_started || slot < 0) return;
    final address = _addressOf(channel);
    if (address == null) return;
    final mc = _channelsByAddress[address]!;
    if (!mc.appliedSends.containsKey(slot)) return;
    final clamped = level.clamp(0.0, 1.0);
    _gateway.setSendLevel(mc.channel.id, slot, clamped);
    mc.appliedSends[slot]!.level = clamped;
    if (_sendGesture == (address: address, slot: slot)) {
      _sendGestureLevel = clamped;
      return;
    }
    final strip = _storedStrip(address);
    if (strip == null || slot >= strip.sends.length) return;
    _persistSends(
      address,
      _withSendAt(
        strip.sends,
        slot,
        strip.sends[slot].copyWith(level: clamped),
      ),
    );
  }

  /// Marks the start of a send-level drag on [slot] of [channel]: subsequent
  /// [setChannelSendLevel] calls ram the gateway without journaling, coalescing
  /// into one payload command on [endSendLevelGesture]. Flushes any unfinished
  /// previous send gesture first.
  void beginSendLevelGesture(MixerChannel channel, int slot) {
    if (!_started) return;
    final address = _addressOf(channel);
    if (address == null ||
        !_channelsByAddress[address]!.appliedSends.containsKey(slot)) {
      return;
    }
    final pending = _sendGesture;
    if (pending != null && pending != (address: address, slot: slot)) {
      _sendGesture = null;
      _flushSendGesture(pending);
    }
    _sendGesture = (address: address, slot: slot);
    _sendGestureLevel = _channelsByAddress[address]!.appliedSends[slot]!.level;
  }

  /// Marks the end of a send-level drag on [slot] of [channel] and flushes the
  /// coalesced level as one journaled payload command. No-op when no gesture is
  /// live for that slot.
  void endSendLevelGesture(MixerChannel channel, int slot) {
    final address = _addressOf(channel);
    if (address == null || _sendGesture != (address: address, slot: slot)) {
      return;
    }
    _sendGesture = null;
    _flushSendGesture((address: address, slot: slot));
  }

  void _flushSendGesture(({EntityAddress address, int slot}) gesture) {
    final strip = _storedStrip(gesture.address);
    if (strip == null || gesture.slot >= strip.sends.length) return;
    _persistSends(
      gesture.address,
      _withSendAt(
        strip.sends,
        gesture.slot,
        strip.sends[gesture.slot].copyWith(level: _sendGestureLevel),
      ),
    );
  }

  /// The [MixStrip] stored in the entity **or group bus** at [address], or `null`
  /// when nothing sits there. A send may live on either (design §3).
  MixStrip? _storedStrip(EntityAddress address) {
    final payload = _mixRegistry.nodeAt(address) is RegistryGroup
        ? _mixRegistry.groupAt(address)?.payload
        : _mixRegistry.entityAt(address)?.payload;
    if (payload is MixStrip) return payload;
    if (payload is Map) {
      return MixStrip.fromJson(payload.cast<String, Object?>());
    }
    return null;
  }

  /// [sends] with [send] placed at [slot], padded with copies of the slot before
  /// it when [slot] is past the end (sends are dense, slot = index).
  List<MixSend> _withSendAt(List<MixSend> sends, int slot, MixSend send) {
    final next = [...sends];
    while (next.length <= slot) {
      next.add(send);
    }
    next[slot] = send;
    return next;
  }

  List<MixSend> _withSendRemovedAt(List<MixSend> sends, int slot) =>
      [...sends]..removeAt(slot);

  /// Writes [sends] into the `mix.` node at [address] as a journaled payload
  /// command (de-duped by JSON like [_persistChannelState]); the ensuing sync
  /// reconciles the gateway. Handles both an entity strip and a group bus.
  void _persistSends(EntityAddress address, List<MixSend> sends) {
    final strip = _storedStrip(address);
    if (strip == null) return;
    final payload = strip.copyWith(sends: sends).toJson();
    final node = _mixRegistry.nodeAt(address);
    final currentPayload = node is RegistryGroup
        ? node.payload
        : _mixRegistry.entityAt(address)?.payload;
    if (jsonEncode(currentPayload) == jsonEncode(payload)) return;
    final command = node is RegistryGroup
        ? UpdateGroupPayloadCommand(_mixRegistry, address, payload)
        : UpdateEntityPayloadCommand(_mixRegistry, address, payload);
    command.apply();
    _recordCommand?.call(command);
  }

  /// Publishes [channel]'s current live state (voice, volume, mute, solo) into
  /// its `mix.` registry entity as a journaled [UpdateEntityPayloadCommand] — the
  /// payload-edit path issue #135 built and #136 reuses for the mix epic. The
  /// parts a [MixerChannel] does not model — the return flag and sends (issue
  /// #166) — are read back off the stored payload and preserved. De-duped by
  /// encoded JSON, so a set that lands on the already-stored value (or restoring a
  /// strip to disk state) never dirties the project or bloats the journal. No-op
  /// when the channel has no backing entity (e.g. the master).
  void _persistChannelState(MixerChannel channel) {
    final address = _addressOf(channel);
    if (address == null) return;
    // A group bus stores its state on the group's own payload (design §3), a
    // strip on the entity's — persist to whichever sits at the address.
    final node = _mixRegistry.nodeAt(address);
    final currentPayload = node is RegistryGroup
        ? node.payload
        : _mixRegistry.entityAt(address)?.payload;
    if (node == null) return;
    final existing = currentPayload is Map
        ? MixStrip.fromJson(currentPayload.cast<String, Object?>())
        : const MixStrip(voice: 1);
    final payload = existing
        .copyWith(
          voice: channel.voice,
          volume: channel.volume,
          muted: channel.muted,
          soloed: channel.soloed,
        )
        .toJson();
    if (jsonEncode(currentPayload) == jsonEncode(payload)) return;
    final command = node is RegistryGroup
        ? UpdateGroupPayloadCommand(_mixRegistry, address, payload)
        : UpdateEntityPayloadCommand(_mixRegistry, address, payload);
    command.apply(); // notifies → _syncChannelsFromRegistry keeps the channel
    _recordCommand?.call(command);
  }

  void _emit(Timer _) {
    if (!_started) return;
    final sampleRate = _gateway.activeSampleRate;
    final latencyMs = sampleRate > 0
        ? (_gateway.activeOutputLatency / sampleRate) * 1000
        : 0.0;
    final masterPeak = _gateway.masterPeak;
    _masterChannel.applyPeak(masterPeak);
    for (final ch in _userChannels) {
      ch.applyPeak(_gateway.channelPeak(ch.id));
    }
    _telemetry.add(
      EngineTelemetry(
        cpuLoad: _gateway.cpuLoad,
        missedCallbacks: _gateway.missedCallbacks,
        masterPeak: masterPeak,
        sampleRate: sampleRate,
        bufferSize: _gateway.activeBufferSize,
        latencyMs: latencyMs,
      ),
    );
  }

  /// Release stream + notifier resources. Call when the host widget tree
  /// is permanently torn down (e.g. app dispose).
  Future<void> dispose() async {
    stop();
    _mirrorBinder.dispose();
    _mixRegistry.removeListener(_syncChannelsFromRegistry);
    if (_ownsMixRegistry) _mixRegistry.dispose();
    _testSignal.dispose();
    _masterVolume.dispose();
    _masterMuted.dispose();
    _masterChannel.dispose();
    _channels.dispose();
    _mixTree.dispose();
    _returns.dispose();
    _lastAudioNotice.dispose();
    await _telemetry.close();
  }
}

/// A `mix.` node flattened out of the tree for reconciliation: its [address],
/// the [parentAddress] its gateway channel hangs from (`null` = master, or a
/// return outside the tree), whether it is a return ([isReturn]), whether it is
/// a group bus ([isGroup] — a framed section in the rack), and the [strip]
/// payload driving its voice / volume / mute / solo / sends.
class _MixNode {
  _MixNode(
    this.address,
    this.parentAddress,
    this.isReturn,
    this.isGroup,
    this.strip,
  );

  final EntityAddress address;
  final EntityAddress? parentAddress;
  final bool isReturn;
  final bool isGroup;
  final MixStrip strip;
}

/// Mutable scratch node used while nesting the flat [_MixNode] list into the
/// immutable [MixTreeNode] forest [PhiEngine.mixTree] exposes.
class _MixTreeBuilder {
  _MixTreeBuilder(this.channel, this.address, this.isGroup);

  final MixerChannel channel;
  final EntityAddress address;
  final bool isGroup;
  final List<_MixTreeBuilder> children = [];

  MixTreeNode freeze() => MixTreeNode(
    channel: channel,
    address: address,
    isGroup: isGroup,
    children: List<MixTreeNode>.unmodifiable(children.map((c) => c.freeze())),
  );
}

/// The engine's live handle on a materialised `mix.` channel: its [channel]
/// (identity + live volume/mute/solo/peak), whether it is a return, the gateway
/// [parentId] currently applied (so a re-parent is only issued on a real change),
/// and the aux sends already wired ([appliedSends], keyed by slot) so the second
/// pass re-sends only what changed.
class _MaterialisedChannel {
  _MaterialisedChannel(this.channel, {required this.isReturn, this.parentId});

  final MixerChannel channel;
  final bool isReturn;
  int? parentId;
  final Map<int, _AppliedSend> appliedSends = {};
}

/// One aux send already wired at the gateway — the target return id, the last
/// level pushed, and the pre/post-fader tap — so the sync diffs against it.
class _AppliedSend {
  _AppliedSend(this.returnId, this.level, this.preFader);

  final int returnId;
  double level;
  final bool preFader;
}
