import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/midi/custom_transform_registry.dart';
import '../domain/midi/midi_clip_seed.dart';
import '../domain/midi/store/clip_document.dart';
import '../domain/midi/store/midi_transform_codec.dart';
import '../domain/mix/mix_strip.dart';
import '../domain/project/app_settings/audio_settings.dart';
import '../domain/project/commands/create_entity_command.dart';
import '../domain/project/commands/move_entity_command.dart';
import '../domain/project/commands/remove_entity_command.dart';
import '../domain/project/commands/update_entity_payload_command.dart';
import '../domain/project/entity_address.dart';
import '../domain/project/name_slug.dart';
import '../domain/project/project_command.dart';
import '../domain/project/project_registry.dart';
import '../domain/project/registry_entity.dart';
import '../domain/project/registry_kinds.dart';
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

  /// The live `MixerChannel` materialised for each `mix.` entity, keyed by
  /// address so a re-sync preserves channel identity (and its live volume/peak).
  final Map<EntityAddress, MixerChannel> _channelsByAddress = {};

  /// The materialised user channels in registry order — rebuilt on every sync.
  final List<MixerChannel> _userChannels = [];
  final ValueNotifier<List<MixerChannel>> _channels =
      ValueNotifier<List<MixerChannel>>(const []);
  int _voiceCursor = 1;

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
  /// directly. Drives the engine's master channel via [setMasterVolume].
  ValueListenable<double> get masterVolume => _masterVolume;

  /// The master mixer channel. Always present, never destroyed. Mute and
  /// solo on the master are no-ops by design — there is nothing to mix
  /// against it.
  MixerChannel get masterChannel => _masterChannel;

  /// Live list of user channels (master excluded). Fires when channels are
  /// added or removed; per-channel state changes (volume, mute, solo, peak)
  /// fire on the individual [MixerChannel] instead.
  ValueListenable<List<MixerChannel>> get channels => _channels;

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
    for (final ch in _channelsByAddress.values) {
      if (_started) _gateway.destroyChannel(ch.id);
      ch.dispose();
    }
    _channelsByAddress.clear();
    _userChannels.clear();
    _channels.value = const [];
  }

  /// Reconciles the materialised channels with the `mix.` entities in
  /// [_mixRegistry]: creates a gateway channel + `MixerChannel` for each new
  /// entity, drops those whose entity is gone, and reorders to match the tree —
  /// the "engine consumes the registry" half of design §8. Preserves the
  /// `MixerChannel` for an entity that persists, so its live volume/mute/solo/
  /// peak survive an unrelated tree change. No-op before [start] (no gateway to
  /// create channels on) and while applying nothing changes.
  void _syncChannelsFromRegistry() {
    if (!_started) return;
    final desired = <EntityAddress>[];
    for (final node in _mixRegistry.childrenOfKind(RegistryKinds.mix)) {
      if (node is! RegistryEntity) continue;
      desired.add(
        EntityAddress(kind: RegistryKinds.mix, segments: [node.name]),
      );
    }

    // Drop channels whose entity no longer exists.
    final gone = _channelsByAddress.keys
        .where((address) => !desired.contains(address))
        .toList();
    for (final address in gone) {
      final ch = _channelsByAddress.remove(address)!;
      _gateway.destroyChannel(ch.id);
      ch.dispose();
    }

    // Create channels for new entities, in registry order.
    for (final address in desired) {
      if (_channelsByAddress.containsKey(address)) continue;
      final strip = MixStrip.fromJson(
        (_mixRegistry.entityAt(address)!.payload as Map)
            .cast<String, Object?>(),
      );
      final id = _gateway.createChannel(strip.name);
      // Restore the persisted live mix state (issue #136) onto the fresh
      // channel; the effective gateway volume is pushed by the solo-aware sweep
      // below, once every channel's soloed flag is known.
      _channelsByAddress[address] =
          MixerChannel.user(id: id, name: strip.name, voice: strip.voice)
            ..applyVolume(strip.volume)
            ..applyMuted(strip.muted)
            ..applySoloed(strip.soloed);
    }

    _userChannels
      ..clear()
      ..addAll([for (final address in desired) _channelsByAddress[address]!]);
    _channels.value = List<MixerChannel>.unmodifiable(_userChannels);
    // Solo is global, so re-push effective volume across the whole set.
    for (final ch in _userChannels) {
      _pushEffectiveVolume(ch);
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

  /// Set the master-channel volume. Clamped to `[0.0, 1.0]`. No-op before
  /// [start].
  void setMasterVolume(double value) {
    if (!_started) return;
    final clamped = value.clamp(0.0, 1.0);
    _gateway.masterVolume = clamped;
    _masterVolume.value = clamped;
    _masterChannel.applyVolume(clamped);
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
      payload: MixStrip(name: resolvedName, voice: voice).toJson(),
    );
    command.apply(); // notifies → _syncChannelsFromRegistry materialises it
    _recordCommand?.call(command);
    return _channelsByAddress[address]!;
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

  /// Renames a user channel: updates its display name in the `mix.` payload and,
  /// when the new name slugs to a different address, **moves** the entity to that
  /// slug so the address follows the name — "rename = refactor" (design §4), which
  /// rewrites any back-references to the channel as one journaled command. No-op
  /// for the master channel, an instance the engine no longer holds, or a blank /
  /// unchanged name. The live volume/mute/solo survive the move (they ride the
  /// payload the strip is rematerialised from). Both the payload update and the
  /// move are recorded for dirty-tracking + journaling.
  void renameChannel(MixerChannel channel, String name) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    final address = _addressOf(channel);
    if (address == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == channel.name) return;

    // Snapshot the live state onto the renamed strip so a move (which tears the
    // channel down and rematerialises it from this payload) preserves the fader
    // value, mute and solo — not just the name.
    final renamed = MixStrip(
      name: trimmed,
      voice: channel.voice,
      volume: channel.volume,
      muted: channel.muted,
      soloed: channel.soloed,
    ).toJson();

    // 1. Persist the new display name into the payload at the current address —
    //    so if the address changes below, the rematerialised channel already
    //    carries the new name.
    final update = UpdateEntityPayloadCommand(_mixRegistry, address, renamed);
    update.apply();
    _recordCommand?.call(update);

    // 2. Follow the name with the address slug when it actually changes.
    final newSlug = NameSlug.of(trimmed, fallback: 'channel');
    if (newSlug == address.name) {
      // The slug is unchanged (only display casing/spacing differs), so the sync
      // does not recreate the channel — push the new name onto the live one.
      channel.applyName(trimmed);
      return;
    }
    final newAddress = _uniqueMixAddress(trimmed);
    final move = MoveEntityCommand(_mixRegistry, address, newAddress);
    move.apply(); // notifies → sync rematerialises the channel at the new slug
    _recordCommand?.call(move);
  }

  /// The registry address of a materialised [channel], or `null` when the engine
  /// no longer holds it.
  EntityAddress? _addressOf(MixerChannel channel) {
    for (final entry in _channelsByAddress.entries) {
      if (identical(entry.value, channel)) return entry.key;
    }
    return null;
  }

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
    if (!_userChannels.contains(channel)) return;
    channel.applyVolume(clamped);
    _pushEffectiveVolume(channel);
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

  /// Mute or unmute a user channel. Master mute is intentionally unsupported
  /// (use volume instead). Triggers a solo-aware re-evaluation across all
  /// user channels. Discrete, so it persists immediately (issue #136).
  void setChannelMuted(MixerChannel channel, {required bool muted}) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    channel.applyMuted(muted);
    _pushEffectiveVolume(channel);
    _persistChannelState(channel);
  }

  /// Toggle a channel's solo flag. When at least one user channel is
  /// soloed, every non-soloed user channel is silenced at the gateway
  /// until solo is cleared.
  void setChannelSoloed(MixerChannel channel, {required bool soloed}) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    final wasAnySoloed = _userChannels.any((c) => c.soloed);
    channel.applySoloed(soloed);
    final isAnySoloed = _userChannels.any((c) => c.soloed);
    if (wasAnySoloed != isAnySoloed) {
      for (final c in _userChannels) {
        _pushEffectiveVolume(c);
      }
    } else {
      _pushEffectiveVolume(channel);
    }
    // Only the toggled channel's own soloed flag is persisted state; the effect
    // on other channels is derived (effective volume), not saved.
    _persistChannelState(channel);
  }

  void _pushEffectiveVolume(MixerChannel channel) {
    final anySoloed = _userChannels.any((c) => c.soloed);
    final silenced = channel.muted || (anySoloed && !channel.soloed);
    final effective = silenced ? 0.0 : channel.volume;
    _gateway.setChannelVolume(channel.id, effective);
  }

  /// Publishes [channel]'s current live state (name, voice, volume, mute, solo)
  /// into its `mix.` registry entity as a journaled [UpdateEntityPayloadCommand]
  /// — the payload-edit path issue #135 built and #136 reuses for the mix epic.
  /// De-duped by encoded JSON, so a set that lands on the already-stored value
  /// (or restoring a strip to disk state) never dirties the project or bloats the
  /// journal. No-op when the channel has no backing entity (e.g. the master).
  void _persistChannelState(MixerChannel channel) {
    final address = _addressOf(channel);
    if (address == null) return;
    final entity = _mixRegistry.entityAt(address);
    if (entity == null) return;
    final payload = MixStrip(
      name: channel.name,
      voice: channel.voice,
      volume: channel.volume,
      muted: channel.muted,
      soloed: channel.soloed,
    ).toJson();
    if (jsonEncode(entity.payload) == jsonEncode(payload)) return;
    final command = UpdateEntityPayloadCommand(_mixRegistry, address, payload);
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
    _masterChannel.dispose();
    _channels.dispose();
    _lastAudioNotice.dispose();
    await _telemetry.close();
  }
}
