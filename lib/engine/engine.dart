import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/midi/midi_clip_seed.dart';
import 'bridge/macbear_scene_renderer.dart';
import 'bridge/midi_gateway.dart';
import 'bridge/patcher_gateway.dart';
import 'bridge/real_midi_gateway.dart';
import 'bridge/real_patcher_gateway.dart';
import 'bridge/real_yse_gateway.dart';
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
    Duration telemetryInterval = const Duration(milliseconds: 50),
  }) : _sceneRenderer = sceneRenderer,
       _patcherGateway = patcherGateway,
       _midiGateway = midiGateway,
       _telemetryInterval = telemetryInterval;

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
    _stateMachine = StateMachineController();
    // MIDI subsystem is optional — tests that don't inject a MidiGateway get
    // an engine without a player (engine.midi throws). When wired, it owns
    // the demo chain + its editor so playback and the piano-roll editor
    // share one source clip.
    final mg = _midiGateway;
    if (mg != null) {
      _midi = EngineMidiController(chain: defaultDemoChain(), gateway: mg);
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
      _midi?.dispose();
      _midi = null;
      _disposeUserChannels();
      _gateway.close();
      _sceneRenderer?.dispose();
      _started = false;
    }
    _testSignal.value = false;
  }

  void _disposeUserChannels() {
    for (final ch in _userChannels) {
      ch.dispose();
    }
    _userChannels.clear();
    _channels.value = const [];
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

  /// Append a new user channel. Picks the next voice slot in `[1, 6]`,
  /// wrapping. No-op before [start]. Returns the created [MixerChannel].
  MixerChannel addChannel({String? name}) {
    if (!_started) {
      throw StateError('PhiEngine.addChannel called before start()');
    }
    final voice = _voiceCursor;
    _voiceCursor = (_voiceCursor % 6) + 1;
    final resolvedName = name ?? 'ch ${_userChannels.length + 1}';
    final id = _gateway.createChannel(resolvedName);
    final ch = MixerChannel.user(id: id, name: resolvedName, voice: voice);
    _userChannels.add(ch);
    _channels.value = List<MixerChannel>.unmodifiable(_userChannels);
    return ch;
  }

  /// Remove a user channel. No-op for the master channel or an unknown
  /// instance. Disposes the [MixerChannel]'s listeners.
  void removeChannel(MixerChannel channel) {
    if (channel.isMaster) return;
    if (!_userChannels.remove(channel)) return;
    _gateway.destroyChannel(channel.id);
    _channels.value = List<MixerChannel>.unmodifiable(_userChannels);
    channel.dispose();
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
    _testSignal.dispose();
    _masterVolume.dispose();
    _masterChannel.dispose();
    _channels.dispose();
    await _telemetry.close();
  }
}
