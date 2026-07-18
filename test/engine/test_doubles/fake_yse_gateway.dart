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
/// hardware; [openAudioDevice] reflects the chosen rate / buffer into the
/// active-state fields, and [unopenableDeviceNames] simulates a device that is
/// present but refuses to open (the design §5 fallback path).
class FakeYseGateway implements YseGateway {
  final List<String> calls = [];
  bool initialised = false;
  bool audioTestOn = false;

  /// Fabricated libYSE version + resolved library path the diagnostics section
  /// reads back (design §6). Reassign to model other values (or an unset path).
  String engineVersionValue = 'fake-yse 0.0.0';
  String? libraryPathValue = r'C:\fake\yse\bin';
  double cpuLoadValue = 0;
  int missedCallbacksValue = 0;
  double activeSampleRateValue = 0;
  int activeBufferSizeValue = 0;
  int activeOutputLatencyValue = 0;

  final StreamController<void> _midiActivity =
      StreamController<void>.broadcast();

  /// Push a synthetic MIDI tick — drives listeners as if a hardware port
  /// had delivered an event.
  void emitMidiActivity() => _midiActivity.add(null);

  @override
  Stream<void> get midiActivity => _midiActivity.stream;

  @override
  void init() {
    calls.add('init');
    initialised = true;
  }

  @override
  void initOffline() {
    calls.add('initOffline');
    initialised = true;
  }

  @override
  void close() {
    calls.add('close');
    initialised = false;
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
  int get missedCallbacks => missedCallbacksValue;

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
  int createChannel(String name) {
    final id = _nextChannelId++;
    calls.add('createChannel:$id:$name');
    channels[id] = FakeChannel(name);
    return id;
  }

  @override
  void destroyChannel(int channelId) {
    calls.add('destroyChannel:$channelId');
    channels.remove(channelId);
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

  /// Close the internal stream controller. Call from test teardown to keep
  /// `flutter test --reporter expanded` from leaking pending subscriptions.
  Future<void> dispose() => _midiActivity.close();
}

/// Per-channel state the fake records and the engine writes to.
class FakeChannel {
  FakeChannel(this.name);

  final String name;
  double volume = 1.0;
  double peak = 0.0;
}
