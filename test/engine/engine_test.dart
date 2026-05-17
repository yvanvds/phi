import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/engine_telemetry.dart';

import 'test_doubles/fake_yse_gateway.dart';

void main() {
  group('PhiEngine', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('start() initialises gateway and begins update loop', () {
      engine.start();

      expect(engine.isStarted, isTrue);
      expect(gateway.initialised, isTrue);
      expect(gateway.calls, containsAllInOrder(<String>['init']));
      expect(
        gateway.calls.any((c) => c.startsWith('startUpdateTimer')),
        isTrue,
      );
    });

    test('start() is idempotent', () {
      engine.start();
      engine.start();

      final inits = gateway.calls.where((c) => c == 'init').length;
      expect(inits, 1);
    });

    test('stop() closes gateway and clears test-signal armed state', () {
      engine.start();
      engine.setTestSignal(on: true);
      expect(engine.testSignal.value, isTrue);

      engine.stop();

      expect(engine.isStarted, isFalse);
      expect(gateway.initialised, isFalse);
      expect(engine.testSignal.value, isFalse);
    });

    test('setTestSignal forwards to gateway and updates listenable', () {
      engine.start();

      engine.setTestSignal(on: true);
      expect(gateway.audioTestOn, isTrue);
      expect(engine.testSignal.value, isTrue);

      engine.setTestSignal(on: false);
      expect(gateway.audioTestOn, isFalse);
      expect(engine.testSignal.value, isFalse);
    });

    test('setTestSignal is a no-op before start()', () {
      engine.setTestSignal(on: true);

      expect(gateway.audioTestOn, isFalse);
      expect(engine.testSignal.value, isFalse);
    });

    test('telemetry stream emits gateway snapshots while running', () async {
      gateway.cpuLoadValue = 0.42;
      gateway.missedCallbacksValue = 3;
      engine.start();

      final EngineTelemetry first = await engine.telemetry.first.timeout(
        const Duration(seconds: 1),
      );

      expect(first.cpuLoad, closeTo(0.42, 1e-9));
      expect(first.missedCallbacks, 3);
    });
  });
}
