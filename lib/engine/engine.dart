import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/midi/midi_clip_seed.dart';
import '../domain/mix/mix_strip.dart';
import '../domain/project/commands/create_entity_command.dart';
import '../domain/project/commands/remove_entity_command.dart';
import '../domain/project/entity_address.dart';
import '../domain/project/name_slug.dart';
import '../domain/project/project_command.dart';
import '../domain/project/project_registry.dart';
import '../domain/project/registry_entity.dart';
import '../domain/project/registry_kinds.dart';
import '../domain/runtime/runtime_variable_registry.dart';
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

  /// The live `MixerChannel` materialised for each `mix.` entity, keyed by
  /// address so a re-sync preserves channel identity (and its live volume/peak).
  final Map<EntityAddress, MixerChannel> _channelsByAddress = {};

  /// The materialised user channels in registry order — rebuilt on every sync.
  final List<MixerChannel> _userChannels = [];
  final ValueNotifier<List<MixerChannel>> _channels =
      ValueNotifier<List<MixerChannel>>(const []);
  int _voiceCursor = 1;

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
  /// strips, and starting a new one clears them. Idempotent when [registry] is
  /// already bound (it only refreshes [recordCommand]).
  void bindProject(
    ProjectRegistry registry, {
    void Function(ProjectCommand)? recordCommand,
  }) {
    if (identical(registry, _mixRegistry)) {
      _recordCommand = recordCommand;
      return;
    }
    _mixRegistry.removeListener(_syncChannelsFromRegistry);
    if (_ownsMixRegistry) _mixRegistry.dispose();
    _mixRegistry = registry;
    _ownsMixRegistry = false;
    _recordCommand = recordCommand;
    _mixRegistry.addListener(_syncChannelsFromRegistry);
    _mirrorBinder.bind(_mixRegistry);
    _teardownChannels();
    _syncChannelsFromRegistry();
  }

  /// Initialise the engine, start the update loop, begin emitting telemetry.
  void start() {
    if (_started) return;
    _gateway.init();
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
      _channelsByAddress[address] = MixerChannel.user(
        id: id,
        name: strip.name,
        voice: strip.voice,
      );
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
  }

  /// Mute or unmute a user channel. Master mute is intentionally unsupported
  /// (use volume instead). Triggers a solo-aware re-evaluation across all
  /// user channels.
  void setChannelMuted(MixerChannel channel, {required bool muted}) {
    if (!_started || channel.isMaster) return;
    if (!_userChannels.contains(channel)) return;
    channel.applyMuted(muted);
    _pushEffectiveVolume(channel);
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
  }

  void _pushEffectiveVolume(MixerChannel channel) {
    final anySoloed = _userChannels.any((c) => c.soloed);
    final silenced = channel.muted || (anySoloed && !channel.soloed);
    final effective = silenced ? 0.0 : channel.volume;
    _gateway.setChannelVolume(channel.id, effective);
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
    await _telemetry.close();
  }
}
