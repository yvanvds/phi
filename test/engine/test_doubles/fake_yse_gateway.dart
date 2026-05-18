import 'dart:async';

import 'package:phi/engine/bridge/yse_gateway.dart';

/// In-memory [YseGateway] used in unit and widget tests.
///
/// Records every call against the engine so tests can assert call sequence
/// without touching `package:yse` or its native library.
class FakeYseGateway implements YseGateway {
  final List<String> calls = [];
  bool initialised = false;
  bool audioTestOn = false;
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
  void close() {
    calls.add('close');
    initialised = false;
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
