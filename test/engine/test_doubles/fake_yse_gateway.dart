import 'dart:async';

import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_exception.dart';
import 'package:phi/engine/bridge/audio_device_state.dart';
import 'package:phi/engine/bridge/yse_gateway.dart';

/// In-memory [YseGateway] used in unit and widget tests.
///
/// Records every call against the engine so tests can assert call sequence
/// without touching `package:yse` or its native library. Fabricates an audio
/// device list ([devices]) so the settings window is fully drivable without
/// hardware; [init] and [openAudioDevice] reflect what the engine opened into
/// the active-state fields, [close] tears that state back down the way
/// `System::close()` does, and [unopenableDeviceNames] simulates a device that
/// is present but refuses to open (the design §5 fallback path).
///
/// The rule this double is held to: a call with an *observable state effect* on
/// the real gateway must reproduce that effect here, not merely append to
/// [calls]. A fake that records without transitioning tells consumers a lie
/// that no unit test can catch, because every test is reading the same lie
/// (issues #398, #399).
class FakeYseGateway implements YseGateway {
  final List<String> calls = [];
  bool initialised = false;
  bool audioTestOn = false;

  /// Fabricated libYSE version + resolved library path the diagnostics section
  /// reads back (design §6). Reassign to model other values (or an unset path).
  String engineVersionValue = 'fake-yse 0.0.0';
  String? libraryPathValue = r'C:\fake\yse\bin';
  double cpuLoadValue = 0;

  /// The engine's device-stall gauge: consecutive control ticks with no audio
  /// callback. Drive it to model a healthy device (a transient `1`) or a real
  /// stall (a sustained run) — see `AudioStallTracker`.
  int deviceStallTicksValue = 0;
  double activeSampleRateValue = 0;
  int activeBufferSizeValue = 0;
  int activeOutputLatencyValue = 0;

  final StreamController<void> _midiActivity =
      StreamController<void>.broadcast();

  /// Whether the gateway is currently subscribed to its MIDI inputs, as
  /// `_openMidiInputs()` / `_closeMidiInputs()` model it on the real gateway.
  /// A fresh fake is open so it can be used as a bare activity source; [close]
  /// shuts it, and a later [init] / [initOffline] re-opens it.
  bool _midiInputsOpen = true;

  /// Push a synthetic MIDI tick — drives listeners as if a hardware port had
  /// delivered an event. Silent after [close]: the real gateway has cancelled
  /// its port subscriptions by then, so hardware traffic reaches no listener
  /// until the engine is initialised again.
  void emitMidiActivity() {
    if (!_midiInputsOpen) return;
    _midiActivity.add(null);
  }

  @override
  Stream<void> get midiActivity => _midiActivity.stream;

  @override
  void init() {
    calls.add('init');
    initialised = true;
    _midiInputsOpen = true;
    // The native `System::init()` brings the platform-default device up with
    // it — only `initOffline()` comes up device-less. Reflect that here, or a
    // fake that booted the default device reads back as "no device open" and
    // every consumer of `activeAudioState()` (the status-bar health monitor,
    // the latency chips) sees a machine whose audio just fell away.
    _openPlatformDefault();
  }

  @override
  void initOffline() {
    calls.add('initOffline');
    initialised = true;
    _midiInputsOpen = true;
  }

  /// Brings the platform default (the first entry of [devices]) up in the live
  /// state, as `System::init()` does natively. Leaves [openedDevice] alone —
  /// that records *explicit* [openAudioDevice] calls, which is what the device
  /// rules (design §5) are asserted through. A machine with no audio hardware
  /// (or whose default refuses to open) stays device-less.
  void _openPlatformDefault() {
    if (devices.isEmpty) return;
    final target = devices.first;
    if (unopenableDeviceNames.contains(target.name)) return;
    activeSampleRateValue = target.sampleRates.isNotEmpty
        ? target.sampleRates.first
        : 0;
    activeBufferSizeValue = target.defaultBufferSize;
    activeOutputLatencyValue = target.outputLatency;
  }

  @override
  void close() {
    calls.add('close');
    initialised = false;
    // `close()` is not a recording — it tears the engine down. The real one
    // closes the MIDI inputs, destroys every channel it minted, and calls
    // `System::close()`, which releases the audio device (the engine's own
    // docs: active rate / buffer / latency read `0` "pre-init, after close, or
    // [initOffline] path"). A fake that only flips [initialised] keeps
    // reporting the last opened device's rate and every channel the engine
    // ever created, so anything reading state after a close — an engine
    // restart, a second `start()` in one process, the diagnostics bundle —
    // sees a device that is not there (issue #399).
    _midiInputsOpen = false;
    channels.clear();
    // Deliberately *not* reset: `_nextChannelId`. `RealYseGateway` keeps
    // counting up across a close, so an id is never recycled onto a different
    // channel; a fake that restarted at 1 would hide a stale-id bug.
    activeSampleRateValue = 0;
    activeBufferSizeValue = 0;
    activeOutputLatencyValue = 0;
    // Gauges and meters belong to the running engine: no audio thread means no
    // load, no stall ticks, and no signal on the master.
    cpuLoadValue = 0;
    deviceStallTicksValue = 0;
    masterPeakValue = 0;
    masterPeakOutputs = List<double>.filled(masterPeakOutputs.length, 0);
    // The test signal goes down with the system that was generating it.
    audioTestOn = false;
    // Left alone, because these record what a *test* asked for rather than
    // live engine state: [calls], [openedDevice] / [openLayout] (the explicit
    // opens the device rules are asserted through), [devices],
    // [autoReconnectOn], [masterVolumeValue], and the diagnostics facts
    // ([engineVersionValue], [libraryPathValue]) which the engine reports
    // without a device open.
  }

  @override
  String get engineVersion => engineVersionValue;

  @override
  String? get libraryPath => libraryPathValue;

  /// Fabricated device list handed out by [audioDevices]. Two entries share a
  /// name under different hosts, so tests exercise the name + host identity rule
  /// (design §3). Reassign to model other hardware (or an empty list).
  List<AudioDeviceDescriptor> devices = const [
    AudioDeviceDescriptor(
      name: 'Fake Interface',
      hostName: 'WASAPI',
      inputChannelNames: ['In 1', 'In 2'],
      outputChannelNames: ['Out 1', 'Out 2'],
      sampleRates: [44100.0, 48000.0, 96000.0],
      bufferSizes: [64, 128, 256, 512],
      defaultBufferSize: 256,
      outputLatency: 256,
      inputLatency: 256,
    ),
    AudioDeviceDescriptor(
      name: 'Fake Interface',
      hostName: 'ASIO',
      inputChannelNames: ['In 1', 'In 2'],
      outputChannelNames: ['Out 1', 'Out 2', 'Out 3', 'Out 4'],
      sampleRates: [48000.0, 96000.0],
      bufferSizes: [128, 256],
      defaultBufferSize: 128,
      outputLatency: 128,
      inputLatency: 128,
    ),
  ];

  /// Device names that are present in [devices] but "fail to open" — lets tests
  /// drive the open-failure path (design §5) for a device that is visible yet
  /// refused by the engine.
  final Set<String> unopenableDeviceNames = {};

  /// The descriptor last passed to (or resolved by) [openAudioDevice], or `null`
  /// before any successful open. `<default>` opens record the resolved device.
  AudioDeviceDescriptor? openedDevice;

  /// The layout the last successful [openAudioDevice] opened with.
  SpeakerLayout? openLayout;

  @override
  List<AudioDeviceDescriptor> audioDevices() => devices;

  @override
  void openAudioDevice(
    AudioDeviceDescriptor? descriptor, {
    double? rate,
    int? buffer,
    SpeakerLayout layout = SpeakerLayout.auto,
  }) {
    final AudioDeviceDescriptor target;
    if (descriptor == null) {
      if (devices.isEmpty) {
        throw const AudioDeviceException(
          'no platform-default audio device is available',
        );
      }
      target = devices.first;
    } else {
      final match = _find(descriptor.name, descriptor.hostName);
      if (match == null) {
        throw AudioDeviceException(
          'no audio device named "${descriptor.name}" on '
          '"${descriptor.hostName}" is available',
        );
      }
      target = match;
    }
    if (unopenableDeviceNames.contains(target.name)) {
      throw AudioDeviceException('engine failed to open "${target.name}"');
    }
    calls.add(
      'openAudioDevice:${descriptor?.name ?? '<default>'}:'
      '${rate?.toStringAsFixed(0) ?? 'def'}:${buffer ?? 'def'}:'
      '${layout.wireName}',
    );
    openedDevice = target;
    openLayout = layout;
    // Reflect the choice into the live state so activeAudioState() reads back
    // what was opened — overrides win, else the device's own defaults.
    activeSampleRateValue =
        rate ?? (target.sampleRates.isNotEmpty ? target.sampleRates.first : 0);
    activeBufferSizeValue = buffer ?? target.defaultBufferSize;
    activeOutputLatencyValue = target.outputLatency;
  }

  @override
  AudioDeviceState activeAudioState() => AudioDeviceState(
    sampleRate: activeSampleRateValue,
    bufferSize: activeBufferSizeValue,
    outputLatency: activeOutputLatencyValue,
  );

  /// The last auto-reconnect configuration the engine pushed — `null` until
  /// [setAutoReconnect] runs. Lets a test assert boot enabled it (design §4).
  bool? autoReconnectOn;
  int? autoReconnectDelayMs;

  @override
  void setAutoReconnect({required bool on, int delayMs = 1000}) {
    calls.add('setAutoReconnect:$on:$delayMs');
    autoReconnectOn = on;
    autoReconnectDelayMs = delayMs;
  }

  AudioDeviceDescriptor? _find(String name, String hostName) {
    for (final device in devices) {
      if (device.name == name && device.hostName == hostName) return device;
    }
    return null;
  }

  @override
  void startUpdateTimer([
    Duration interval = const Duration(milliseconds: 16),
  ]) {
    calls.add('startUpdateTimer:${interval.inMilliseconds}');
  }

  @override
  double get cpuLoad => cpuLoadValue;

  @override
  int get deviceStallTicks => deviceStallTicksValue;

  @override
  set audioTest(bool on) {
    calls.add('audioTest:$on');
    audioTestOn = on;
  }

  double masterVolumeValue = 1.0;

  @override
  double get masterVolume => masterVolumeValue;

  @override
  set masterVolume(double value) {
    calls.add('masterVolume:${value.toStringAsFixed(3)}');
    masterVolumeValue = value;
  }

  double masterPeakValue = 0;

  @override
  double get masterPeak => masterPeakValue;

  /// Number of speaker outputs the master channel feeds (design §6). Reassign
  /// to model a non-stereo layout (e.g. 6 for 5.1) before reading meters.
  int masterOutputCountValue = 2;

  /// Per-output post-fader master peaks — seed to drive the master strip's
  /// per-speaker meters. Out-of-range indices read `0`.
  List<double> masterPeakOutputs = [0, 0];

  @override
  int get masterOutputCount => masterOutputCountValue;

  @override
  double masterPeakOutput(int output) =>
      (output >= 0 && output < masterPeakOutputs.length)
      ? masterPeakOutputs[output]
      : 0;

  @override
  double get activeSampleRate => activeSampleRateValue;

  @override
  int get activeBufferSize => activeBufferSizeValue;

  @override
  int get activeOutputLatency => activeOutputLatencyValue;

  /// Public mirror of the per-channel state the engine writes into us.
  /// Tests can read this to assert the gateway received the right values,
  /// or seed `peak` to drive telemetry updates.
  final Map<int, FakeChannel> channels = {};
  int _nextChannelId = 1;

  @override
  int createChannel(String name, {int? parentId}) {
    final id = _nextChannelId++;
    calls.add('createChannel:$id:$name:${parentId ?? 'master'}');
    channels[id] = FakeChannel(name, parentId: parentId);
    return id;
  }

  @override
  void destroyChannel(int channelId) {
    calls.add('destroyChannel:$channelId');
    channels.remove(channelId);
  }

  @override
  void moveChannel(int channelId, [int? parentId]) {
    calls.add('moveChannel:$channelId:${parentId ?? 'master'}');
    final ch = channels[channelId];
    if (ch != null) ch.parentId = parentId;
  }

  @override
  int createReturnChannel(String name, {int sendSlots = 4}) {
    final id = _nextChannelId++;
    calls.add('createReturnChannel:$id:$name:$sendSlots');
    channels[id] = FakeChannel(name, isReturn: true, sendSlots: sendSlots);
    return id;
  }

  @override
  double channelVolume(int channelId) => channels[channelId]?.volume ?? 0;

  @override
  void setChannelVolume(int channelId, double value) {
    calls.add('setChannelVolume:$channelId:${value.toStringAsFixed(3)}');
    final ch = channels[channelId];
    if (ch != null) ch.volume = value;
  }

  @override
  double channelPeak(int channelId) => channels[channelId]?.peak ?? 0;

  @override
  void setSend(
    int channelId,
    int slot,
    int returnId,
    double level,
    bool preFader,
  ) {
    calls.add(
      'setSend:$channelId:$slot:$returnId:'
      '${level.toStringAsFixed(3)}:$preFader',
    );
    final ch = channels[channelId];
    if (ch == null) return;
    // Mirror the engine's illegal-wiring rejection as a silent no-op (design
    // §4): the slot must be in range, the target must be an existing return,
    // and the edge must be neither a self-send nor close a cycle.
    if (!_isLegalSend(channelId, slot, returnId)) return;
    ch.sends[slot] = FakeSend(
      returnId: returnId,
      level: level,
      preFader: preFader,
    );
  }

  @override
  void setSendLevel(int channelId, int slot, double level) {
    calls.add('setSendLevel:$channelId:$slot:${level.toStringAsFixed(3)}');
    final send = channels[channelId]?.sends[slot];
    if (send != null) send.level = level;
  }

  @override
  void clearSend(int channelId, int slot) {
    calls.add('clearSend:$channelId:$slot');
    channels[channelId]?.sends.remove(slot);
  }

  @override
  int channelOutputCount(int channelId) =>
      channels[channelId]?.outputCount ?? 0;

  @override
  double channelPeakOutput(int channelId, int output) =>
      channels[channelId]?.peakOutput(output) ?? 0;

  @override
  double channelPeakPreOutput(int channelId, int output) =>
      channels[channelId]?.prePeakOutput(output) ?? 0;

  /// Whether wiring send [slot] of [channelId] to [returnId] would be accepted
  /// by the engine. Encodes the four rejection cases the engine logs as no-ops.
  bool _isLegalSend(int channelId, int slot, int returnId) {
    final ch = channels[channelId];
    if (ch == null) return false;
    if (slot < 0 || slot >= ch.sendSlots) return false; // out-of-range slot
    if (returnId == channelId) return false; // self-send
    final target = channels[returnId];
    if (target == null || !target.isReturn) return false; // non-return target
    if (_sendReaches(returnId, channelId)) return false; // would close a cycle
    return true;
  }

  /// Whether [from] can already reach [goal] by following existing send edges —
  /// used to reject a return → return edge that would close a cycle.
  bool _sendReaches(int from, int goal, [Set<int>? seen]) {
    if (from == goal) return true;
    seen ??= {};
    if (!seen.add(from)) return false;
    final ch = channels[from];
    if (ch == null) return false;
    for (final send in ch.sends.values) {
      if (_sendReaches(send.returnId, goal, seen)) return true;
    }
    return false;
  }

  /// Close the internal stream controller. Call from test teardown to keep
  /// `flutter test --reporter expanded` from leaking pending subscriptions.
  Future<void> dispose() => _midiActivity.close();
}

/// Per-channel state the fake records and the engine writes to.
class FakeChannel {
  FakeChannel(
    this.name, {
    this.parentId,
    this.isReturn = false,
    int sendSlots = 4,
  }) : sendSlots = isReturn ? sendSlots : 4;

  final String name;
  double volume = 1.0;
  double peak = 0.0;

  /// Parent channel id in the mix tree, or `null` for a child of master.
  /// Meaningless for a return (returns sit outside the tree).
  int? parentId;

  /// Whether this channel is a return bus ([createReturnChannel]) rather than
  /// an ordinary mix-tree channel.
  final bool isReturn;

  /// Number of aux-send slots. Ordinary channels get the engine default of
  /// four; a return fixes its own count at creation.
  final int sendSlots;

  /// Number of speaker outputs this channel feeds. Reassign to model a
  /// non-stereo layout before reading per-output meters.
  int outputCount = 2;

  /// Per-output post- and pre-fader peaks — seed to drive per-speaker meters.
  /// Out-of-range indices read `0`.
  List<double> peakOutputs = [0, 0];
  List<double> prePeakOutputs = [0, 0];

  /// Active sends keyed by slot index.
  final Map<int, FakeSend> sends = {};

  double peakOutput(int output) =>
      (output >= 0 && output < peakOutputs.length) ? peakOutputs[output] : 0;

  double prePeakOutput(int output) =>
      (output >= 0 && output < prePeakOutputs.length)
      ? prePeakOutputs[output]
      : 0;
}

/// One wired aux send: the target return, its level, and pre/post-fader tap.
class FakeSend {
  FakeSend({
    required this.returnId,
    required this.level,
    required this.preFader,
  });

  final int returnId;
  double level;
  final bool preFader;
}
