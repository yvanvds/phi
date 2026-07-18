import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// PhiEngine's boot-from-settings entry points (design §5): `start` routes the
/// stored [AudioSettings] through the device coordinator, and `switchAudioDevice`
/// applies a live change with revert-on-failure — both surfaced through
/// `activeAudioSettings` / `lastAudioNotice`.
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

  test('start() with no stored device opens the default (init)', () {
    engine.start();

    expect(gateway.calls, contains('init'));
    expect(gateway.calls.any((c) => c.startsWith('initOffline')), isFalse);
    expect(engine.activeAudioSettings, const AudioSettings());
    expect(engine.lastAudioNotice.value, isNull);
    // Auto-reconnect is on at boot regardless (design §4).
    expect(gateway.autoReconnectOn, isTrue);
  });

  test('start() with a stored device boots offline and opens it', () {
    engine.start(
      audioSettings: const AudioSettings(
        outputHost: 'ASIO',
        outputDevice: 'Fake Interface',
      ),
    );

    expect(gateway.calls, contains('initOffline'));
    expect(gateway.openedDevice, gateway.devices[1]);
    expect(engine.activeAudioSettings.outputDevice, 'Fake Interface');
    expect(engine.lastAudioNotice.value, isNull);
  });

  test('start() with a missing device falls back and surfaces a notice', () {
    const stored = AudioSettings(
      outputHost: 'ASIO',
      outputDevice: 'Ghost Device',
    );
    engine.start(audioSettings: stored);

    // Fell back to the platform default …
    expect(engine.activeAudioSettings.outputDevice, isNull);
    expect(
      engine.lastAudioNotice.value?.kind,
      AudioNoticeKind.deviceUnavailable,
    );
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
