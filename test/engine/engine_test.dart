import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/engine_telemetry.dart';

import 'test_doubles/fake_patcher_gateway.dart';
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

    test('masterChannel is present and never destroyed', () {
      expect(engine.masterChannel.isMaster, isTrue);
      expect(engine.masterChannel.name, 'master');
    });

    test('addChannel before start() throws StateError', () {
      expect(engine.addChannel, throwsStateError);
    });

    test('addChannel creates a gateway channel and appends to channels', () {
      engine.start();

      final ch1 = engine.addChannel(name: 'drum');
      final ch2 = engine.addChannel(name: 'pad');

      expect(engine.channels.value, [ch1, ch2]);
      expect(gateway.channels[ch1.id]?.name, 'drum');
      expect(gateway.channels[ch2.id]?.name, 'pad');
      expect(ch1.voice, 1);
      expect(ch2.voice, 2);
    });

    test('addChannel cycles voice indices 1..6 then wraps', () {
      engine.start();

      final voices = <int>[
        for (var i = 0; i < 7; i++) engine.addChannel().voice,
      ];

      expect(voices, [1, 2, 3, 4, 5, 6, 1]);
    });

    test('removeChannel destroys the gateway channel and removes it', () {
      engine.start();
      final ch = engine.addChannel(name: 'drum');

      engine.removeChannel(ch);

      expect(engine.channels.value, isEmpty);
      expect(gateway.channels, isEmpty);
      expect(gateway.calls, contains('destroyChannel:${ch.id}'));
    });

    test('removeChannel on master is a no-op', () {
      engine.start();
      engine.removeChannel(engine.masterChannel);

      expect(gateway.calls.any((c) => c.startsWith('destroyChannel')), isFalse);
    });

    test('setChannelVolume clamps and forwards the effective value', () {
      engine.start();
      final ch = engine.addChannel();

      engine.setChannelVolume(ch, 0.4);
      expect(ch.volume, closeTo(0.4, 1e-9));
      expect(gateway.channels[ch.id]!.volume, closeTo(0.4, 1e-9));

      engine.setChannelVolume(ch, 1.7);
      expect(ch.volume, closeTo(1.0, 1e-9));
      expect(gateway.channels[ch.id]!.volume, closeTo(1.0, 1e-9));
    });

    test('setChannelVolume on master routes through setMasterVolume', () {
      engine.start();

      engine.setChannelVolume(engine.masterChannel, 0.3);

      expect(gateway.masterVolumeValue, closeTo(0.3, 1e-9));
      expect(engine.masterVolume.value, closeTo(0.3, 1e-9));
      expect(engine.masterChannel.volume, closeTo(0.3, 1e-9));
    });

    test('setChannelMuted silences the gateway but preserves user volume', () {
      engine.start();
      final ch = engine.addChannel();
      engine.setChannelVolume(ch, 0.7);

      engine.setChannelMuted(ch, muted: true);
      expect(ch.muted, isTrue);
      expect(ch.volume, closeTo(0.7, 1e-9));
      expect(gateway.channels[ch.id]!.volume, 0.0);

      engine.setChannelMuted(ch, muted: false);
      expect(gateway.channels[ch.id]!.volume, closeTo(0.7, 1e-9));
    });

    test('soloing one channel silences the others; clearing restores them', () {
      engine.start();
      final drum = engine.addChannel();
      final pad = engine.addChannel();
      engine.setChannelVolume(drum, 0.8);
      engine.setChannelVolume(pad, 0.5);

      engine.setChannelSoloed(drum, soloed: true);

      expect(gateway.channels[drum.id]!.volume, closeTo(0.8, 1e-9));
      expect(gateway.channels[pad.id]!.volume, 0.0);

      engine.setChannelSoloed(drum, soloed: false);

      expect(gateway.channels[drum.id]!.volume, closeTo(0.8, 1e-9));
      expect(gateway.channels[pad.id]!.volume, closeTo(0.5, 1e-9));
    });

    test('mute on a soloed channel still silences it', () {
      engine.start();
      final drum = engine.addChannel();
      final pad = engine.addChannel();
      engine.setChannelVolume(drum, 0.8);
      engine.setChannelVolume(pad, 0.5);

      engine.setChannelSoloed(drum, soloed: true);
      engine.setChannelMuted(drum, muted: true);

      expect(gateway.channels[drum.id]!.volume, 0.0);
      expect(gateway.channels[pad.id]!.volume, 0.0);
    });

    test('telemetry tick updates each channel\'s peak', () async {
      engine.start();
      final ch = engine.addChannel();
      gateway.masterPeakValue = 0.42;
      gateway.channels[ch.id]!.peak = 0.6;

      await engine.telemetry.first.timeout(const Duration(seconds: 1));

      expect(engine.masterChannel.peak, closeTo(0.42, 1e-9));
      expect(ch.peak, closeTo(0.6, 1e-9));
    });

    test('stop() disposes user channels and clears the list', () {
      engine.start();
      engine.addChannel();
      engine.addChannel();
      expect(engine.channels.value, hasLength(2));

      engine.stop();

      expect(engine.channels.value, isEmpty);
    });

    test('MixerChannel ChangeNotifier fires when its state changes', () {
      engine.start();
      final ch = engine.addChannel();
      var ticks = 0;
      ch.addListener(() => ticks++);

      engine.setChannelVolume(ch, 0.4);
      engine.setChannelMuted(ch, muted: true);
      engine.setChannelSoloed(ch, soloed: true);

      expect(ticks, greaterThanOrEqualTo(3));
    });
  });

  group('PhiEngine with patcher', () {
    late FakeYseGateway gateway;
    late FakePatcherGateway patcherGateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      patcherGateway = FakePatcherGateway();
      engine = PhiEngine(
        gateway,
        patcherGateway: patcherGateway,
        telemetryInterval: const Duration(milliseconds: 20),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
    });

    test('patcher getter throws before start()', () {
      expect(() => engine.patcher, throwsStateError);
    });

    test('start() initialises the patcher gateway but does not mount', () {
      engine.start();

      expect(patcherGateway.initialised, isTrue);
      // Mounting on an empty patcher crashes the audio thread; the
      // surface mounts after seeding a `~dac`.
      expect(patcherGateway.mounted, isFalse);
      expect(patcherGateway.calls.any((c) => c.startsWith('init')), isTrue);
      expect(
        patcherGateway.calls.any((c) => c.startsWith('mountAsSound')),
        isFalse,
      );
    });

    test('controller.mountAudio is idempotent', () {
      engine.start();

      engine.patcher.mountAudio();
      engine.patcher.mountAudio();

      final mounts = patcherGateway.calls.where(
        (c) => c.startsWith('mountAsSound'),
      );
      expect(mounts, hasLength(1));
    });

    test('stop() disposes the patcher gateway and resets the getter', () {
      engine.start();
      engine.stop();

      expect(patcherGateway.initialised, isFalse);
      expect(() => engine.patcher, throwsStateError);
      expect(patcherGateway.calls, contains('dispose'));
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
