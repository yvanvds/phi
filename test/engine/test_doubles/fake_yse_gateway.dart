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
}
