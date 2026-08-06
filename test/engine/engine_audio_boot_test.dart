import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// PhiEngine's audio-device surface (design §5). Since issue #405 there is one
/// entry point per step and no unused twin: `start()` takes no settings and
/// brings the platform default up, `switchAudioDevice` applies a chosen device —
/// the stored one once settings have loaded, or a live pick — with
/// revert-on-failure. Both surface through `activeAudioSettings` /
/// `lastAudioNotice`.
void main() {
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

  test('start() opens the platform default (init)', () {
    engine.start();

    expect(gateway.calls, contains('init'));
    expect(gateway.calls.any((c) => c.startsWith('initOffline')), isFalse);
    expect(engine.activeAudioSettings, const AudioSettings());
    expect(engine.lastAudioNotice.value, isNull);
    // Auto-reconnect is on at boot regardless (design §4).
    expect(gateway.autoReconnectOn, isTrue);
  });

  test('the launch sequence opens the stored device', () {
    // Exactly what `PhiApp` + `Workstation._startProject` run: start the engine,
    // then apply the settings the store has just handed over. `init()`, not
    // `initOffline()` — the engine enumerates devices only while opening one, so
    // an offline boot has nothing to resolve the stored name against and ends in
    // silence (issue #403). There is no `start(audioSettings:)` to test instead;
    // it was the unrun duplicate of these two lines (issue #405).
    engine.start();
    final ok = engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
    );

    expect(ok, isTrue);
    expect(gateway.calls, contains('init'));
    expect(gateway.calls.any((c) => c.startsWith('initOffline')), isFalse);
    expect(gateway.openedDevice, gateway.devices[1]);
    expect(engine.activeAudioSettings.outputDevice, 'Fake Interface');
    expect(engine.lastAudioNotice.value, isNull);
  });

  test('a stored device that is missing stays on the default and notifies', () {
    const stored = AudioSettings(
      outputHost: 'ASIO',
      outputDevice: 'Ghost Device',
    );
    engine.start();
    final ok = engine.switchAudioDevice(stored);

    expect(ok, isFalse);
    // Stayed on the platform default `start()` opened …
    expect(engine.activeAudioSettings.outputDevice, isNull);
    expect(engine.lastAudioNotice.value?.kind, AudioNoticeKind.switchReverted);
    // … while the stored preference (an immutable value) is untouched.
    expect(stored.outputDevice, 'Ghost Device');
  });

  test('switchAudioDevice is a no-op returning false before start()', () {
    final ok = engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
    );

    expect(ok, isFalse);
    expect(gateway.calls.any((c) => c.startsWith('openAudioDevice')), isFalse);
  });

  test('switchAudioDevice applies a live change after start()', () {
    engine.start();

    final ok = engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
    );

    expect(ok, isTrue);
    expect(engine.activeAudioSettings.outputDevice, 'Fake Interface');
    expect(gateway.openedDevice, gateway.devices[1]);
  });

  test('switchAudioDevice to a missing device reverts and notifies', () {
    engine.start();

    final ok = engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost Device'),
    );

    expect(ok, isFalse);
    expect(engine.lastAudioNotice.value?.kind, AudioNoticeKind.switchReverted);
    expect(engine.activeAudioSettings.outputDevice, isNull);
  });
}
