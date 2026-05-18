import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/engine_telemetry.dart';

import 'test_doubles/fake_scene_renderer.dart';
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
      await gateway.dispose();
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

    test('start() seeds masterVolume listenable from gateway', () {
      gateway.masterVolumeValue = 0.7;
      engine.start();

      expect(engine.masterVolume.value, closeTo(0.7, 1e-9));
    });

    test('setMasterVolume clamps to [0, 1] and updates listenable', () {
      engine.start();

      engine.setMasterVolume(0.42);
      expect(gateway.masterVolumeValue, closeTo(0.42, 1e-9));
      expect(engine.masterVolume.value, closeTo(0.42, 1e-9));

      engine.setMasterVolume(1.7);
      expect(gateway.masterVolumeValue, closeTo(1.0, 1e-9));
      expect(engine.masterVolume.value, closeTo(1.0, 1e-9));

      engine.setMasterVolume(-0.3);
      expect(gateway.masterVolumeValue, closeTo(0.0, 1e-9));
      expect(engine.masterVolume.value, closeTo(0.0, 1e-9));
    });

    test('setMasterVolume is a no-op before start()', () {
      engine.setMasterVolume(0.5);

      expect(gateway.calls.any((c) => c.startsWith('masterVolume')), isFalse);
      expect(engine.masterVolume.value, closeTo(1.0, 1e-9));
    });

    test('telemetry stream emits gateway snapshots while running', () async {
      gateway.cpuLoadValue = 0.42;
      gateway.missedCallbacksValue = 3;
      gateway.masterPeakValue = 0.6;
      gateway.activeSampleRateValue = 48000;
      gateway.activeBufferSizeValue = 128;
      gateway.activeOutputLatencyValue = 256;
      engine.start();

      final EngineTelemetry first = await engine.telemetry.first.timeout(
        const Duration(seconds: 1),
      );

      expect(first.cpuLoad, closeTo(0.42, 1e-9));
      expect(first.missedCallbacks, 3);
      expect(first.masterPeak, closeTo(0.6, 1e-9));
      expect(first.sampleRate, closeTo(48000, 1e-9));
      expect(first.bufferSize, 128);
      // 256 samples / 48000 Hz * 1000 = 5.333... ms
      expect(first.latencyMs, closeTo(5.333, 1e-3));
    });

    test('telemetry latencyMs is zero when no device is open', () async {
      gateway.activeSampleRateValue = 0;
      gateway.activeOutputLatencyValue = 0;
      engine.start();

      final EngineTelemetry first = await engine.telemetry.first.timeout(
        const Duration(seconds: 1),
      );

      expect(first.latencyMs, 0);
      expect(first.sampleRate, 0);
      expect(first.bufferSize, 0);
    });

    test('midiActivity stream forwards gateway ticks', () async {
      engine.start();
      final received = <void>[];
      final sub = engine.midiActivity.listen(received.add);

      gateway.emitMidiActivity();
      gateway.emitMidiActivity();
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      await sub.cancel();
    });

    test('sceneRenderer getter is null when none is injected', () {
      expect(engine.sceneRenderer, isNull);
    });
  });

  group('PhiEngine with sceneRenderer', () {
    late FakeYseGateway gateway;
    late FakeSceneRenderer renderer;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      renderer = FakeSceneRenderer();
      engine = PhiEngine(
        gateway,
        sceneRenderer: renderer,
        telemetryInterval: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
    });

    test('sceneRenderer getter returns the injected renderer', () {
      expect(engine.sceneRenderer, same(renderer));
    });

    test('start() initialises the renderer', () {
      engine.start();

      expect(renderer.initialised, isTrue);
      expect(renderer.calls, contains('init'));
    });

    test('stop() disposes the renderer', () {
      engine.start();
      engine.stop();

      expect(renderer.initialised, isFalse);
      expect(renderer.calls, containsAllInOrder(<String>['init', 'dispose']));
    });
  });
}
