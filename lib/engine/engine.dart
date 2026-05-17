import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bridge/real_yse_gateway.dart';
import 'bridge/yse_gateway.dart';
import 'state/engine_telemetry.dart';

/// High-level façade over the YSE audio engine.
///
/// `PhiEngine` is the only thing the rest of the app talks to about audio.
/// It composes a [YseGateway] (injected for testability), owns the engine
/// lifecycle, and exposes live telemetry as a broadcast stream.
class PhiEngine {
  PhiEngine(
    this._gateway, {
    Duration telemetryInterval = const Duration(milliseconds: 50),
  }) : _telemetryInterval = telemetryInterval;

  /// Production constructor — wires the real `package:yse` gateway.
  factory PhiEngine.production() => PhiEngine(RealYseGateway());

  final YseGateway _gateway;
  final Duration _telemetryInterval;

  Timer? _telemetryTimer;
  final StreamController<EngineTelemetry> _telemetry =
      StreamController<EngineTelemetry>.broadcast();
  final ValueNotifier<bool> _testSignal = ValueNotifier<bool>(false);

  bool _started = false;

  /// Whether [start] has been called and [stop] has not.
  bool get isStarted => _started;

  /// Live broadcast of engine telemetry. Listeners receive a new snapshot
  /// every [_telemetryInterval] while the engine is running.
  Stream<EngineTelemetry> get telemetry => _telemetry.stream;

  /// Test-signal toggle. Observable so widgets can reflect the armed state.
  ValueListenable<bool> get testSignal => _testSignal;

  /// Initialise the engine, start the update loop, begin emitting telemetry.
  void start() {
    if (_started) return;
    _gateway.init();
    _gateway.startUpdateTimer();
    _telemetryTimer = Timer.periodic(_telemetryInterval, _emit);
    _started = true;
  }

  /// Stop telemetry, close the engine.
  void stop() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    if (_started) {
      _gateway.close();
      _started = false;
    }
    _testSignal.value = false;
  }

  /// Turn the engine's built-in audio test signal on or off.
  void setTestSignal({required bool on}) {
    if (!_started) return;
    _gateway.audioTest = on;
    _testSignal.value = on;
  }

  void _emit(Timer _) {
    if (!_started) return;
    _telemetry.add(
      EngineTelemetry(
        cpuLoad: _gateway.cpuLoad,
        missedCallbacks: _gateway.missedCallbacks,
      ),
    );
  }

  /// Release stream + notifier resources. Call when the host widget tree
  /// is permanently torn down (e.g. app dispose).
  Future<void> dispose() async {
    stop();
    _testSignal.dispose();
    await _telemetry.close();
  }
}
