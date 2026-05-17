import 'package:yse/yse.dart';

import 'yse_gateway.dart';

/// Production [YseGateway] that forwards every call to `System.instance`.
///
/// Requires `libyse.dll` discoverable at runtime — either next to the
/// executable or pointed at by the `YSE_DLL_PATH` environment variable. See
/// README.md for the Windows setup.
class RealYseGateway implements YseGateway {
  System? _sys;

  System get _system => _sys ??= System.instance;

  @override
  void init() => _system.init();

  @override
  void close() => _system.close();

  @override
  void startUpdateTimer([
    Duration interval = const Duration(milliseconds: 16),
  ]) {
    _system.startUpdateTimer(interval);
  }

  @override
  double get cpuLoad => _system.cpuLoad;

  @override
  int get missedCallbacks => _system.missedCallbacks;

  @override
  set audioTest(bool on) => _system.audioTest = on;

  @override
  double get masterVolume => Channel.master.volume;

  @override
  set masterVolume(double value) => Channel.master.volume = value;
}
