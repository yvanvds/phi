import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/bridge/audio_recovery_status.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// PhiEngine's audio-device surface (design §5). One boot path (issues #405,
/// #449): `requestBootAudio(stored)` names the stored settings, and `start()`
/// opens exactly that device from an offline session — falling back to the
/// platform default with a notice. `switchAudioDevice` applies a live pick on
/// top, with revert-on-failure. Both surface through `activeAudioSettings` /
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

  test('start() with nothing requested opens the platform default', () {
    engine.start();

    expect(gateway.calls, contains('initOffline'));
    expect(gateway.calls, isNot(contains('init')));
    expect(engine.activeAudioSettings, const AudioSettings());
    expect(engine.lastAudioNotice.value, isNull);
    expect(engine.bootAudioNotices, isEmpty);
    // The engine's own auto-reconnect is off since issue #410 — it reopens the
    // platform default rather than the lost device, on every control tick with
    // no backoff. Phi supervises recovery instead, and has nothing to recover
    // from here.
    expect(gateway.autoReconnectOn, isFalse);
    expect(engine.audioRecovery.retrying, isFalse);
    expect(engine.audioRecovery.gaveUp, isFalse);
    // Before `start()` there is no supervisor to ask at all.
    final unstarted = FakeYseGateway();
    addTearDown(unstarted.dispose);
    expect(PhiEngine(unstarted).audioRecovery, AudioRecoveryStatus.idle);
  });

  test('the launch sequence opens the stored device, and only it', () {
    // Exactly what `PhiApp` runs: hand over the stored settings, then start.
    engine.requestBootAudio(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
    );
    engine.start();

    expect(gateway.openedDevice, gateway.devices[1]);
    expect(gateway.calls.where((c) => c.startsWith('openAudioDevice')), [
      'openAudioDevice:Fake Interface:def:def:auto',
    ]);
    expect(engine.activeAudioSettings?.outputDevice, 'Fake Interface');
    expect(engine.lastAudioNotice.value, isNull);
  });

  test('a stored device that is missing falls back to the default, notifies, '
      'and keeps the notice for the shell', () {
    const stored = AudioSettings(
      outputHost: 'ASIO',
      outputDevice: 'Ghost Device',
    );
    engine.requestBootAudio(stored);
    engine.start();

    // On the platform default — a device *is* open, it just has no chosen
    // name, which is not the same as the `null` that means nothing is open
    // (issue #408).
    expect(engine.activeAudioSettings, const AudioSettings());
    expect(engine.lastAudioNotice.value?.kind, AudioNoticeKind.switchReverted);
    // Boot runs before the shell listens, so the notice is retained for it.
    expect(engine.bootAudioNotices.map((n) => n.kind), [
      AudioNoticeKind.switchReverted,
    ]);
    // … while the stored preference (an immutable value) is untouched.
    expect(stored.outputDevice, 'Ghost Device');
  });

  test(
    'a live switch is not a boot notice, and a restart comes back on it',
    () {
      engine.start();
      engine.switchAudioDevice(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost Device'),
      );
      expect(engine.lastAudioNotice.value, isNotNull);
      expect(engine.bootAudioNotices, isEmpty);

      engine.switchAudioDevice(
        const AudioSettings(outputHost: 'ASIO', outputDevice: 'Fake Interface'),
      );
      engine.stop();
      engine.start();
      expect(engine.activeAudioSettings?.outputHost, 'ASIO');
    },
  );

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
    expect(engine.activeAudioSettings?.outputDevice, 'Fake Interface');
    expect(gateway.openedDevice, gateway.devices[1]);
  });

  test('switchAudioDevice to a missing device reverts and notifies', () {
    engine.start();

    final ok = engine.switchAudioDevice(
      const AudioSettings(outputHost: 'ASIO', outputDevice: 'Ghost Device'),
    );

    expect(ok, isFalse);
    expect(engine.lastAudioNotice.value?.kind, AudioNoticeKind.switchReverted);
    // The platform default is still open — "no device chosen", not "no device".
    expect(engine.activeAudioSettings, const AudioSettings());
  });
}
