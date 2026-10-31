import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/audio_device_notice.dart';
import 'package:phi/engine/engine.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that Phi boots audio from the stored settings at launch
/// (design §5), driven through the real [PhiApp] against in-memory fakes: the
/// stored device is opened when present, and a missing one falls back to the
/// default while the stored preference is kept intact.
///
/// This drives the *whole* boot path, not a slice of it: `PhiApp.initState`
/// reads the stored audio section through the settings controller's store and
/// boots the engine straight onto it — offline session, refresh, open exactly
/// the stored device (issue #449). It is the only such path (#405): the shell
/// no longer re-applies the stored device once settings have loaded, so there
/// is no second boot for a test to agree with while production runs another.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  ProjectController buildController({
    required SessionState session,
    required AppSettingsController settings,
  }) => ProjectController(
    session: session,
    settings: settings,
    storeFactory: (_) => FakeProjectStore(),
    journalStoreFactory: (_) => FakeJournalStore(),
    autosaveIntervalOverride: const Duration(hours: 1),
  );

  testWidgets('a stored, present device is opened on launch', (tester) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Fake Interface',
        ),
      ),
    );
    final settings = AppSettingsController(settingsStore);
    final controller = buildController(session: session, settings: settings);

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // The stored ASIO device (not its WASAPI namesake) was opened — and it is
    // the only device boot ever opened: the platform default never came up
    // first to negotiate the session (issue #449) …
    expect(gateway.openedDevice?.name, 'Fake Interface');
    expect(gateway.openedDevice?.hostName, 'ASIO');
    expect(gateway.calls, isNot(contains('init')));
    expect(gateway.calls.where((c) => c.startsWith('openAudioDevice')), [
      'openAudioDevice:Fake Interface:def:def:auto',
    ]);
    expect(engine.activeAudioSettings?.outputDevice, 'Fake Interface');
    expect(engine.lastAudioNotice.value, isNull);
    // … the engine's own auto-reconnect is left off (issue #410 — it reopens the
    // platform default rather than the lost device; Phi supervises recovery),
    // with nothing to recover from here …
    expect(gateway.autoReconnectOn, isFalse);
    expect(engine.audioRecovery.retrying, isFalse);
    // … and nothing rewrote the settings file.
    expect(settingsStore.saveCount, 0);

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });

  testWidgets('a missing device falls back and keeps the preference', (
    tester,
  ) async {
    final gateway = FakeYseGateway();
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(
          outputHost: 'ASIO',
          outputDevice: 'Unplugged Interface',
        ),
      ),
    );
    final settings = AppSettingsController(settingsStore);
    final controller = buildController(session: session, settings: settings);

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // No stored device was opened; the engine stayed on the default — which is
    // an open device with no chosen name, not the `null` that means the engine
    // is on nothing (issue #408).
    expect(engine.activeAudioSettings, const AudioSettings());
    expect(engine.lastAudioNotice.value?.kind, AudioNoticeKind.switchReverted);
    // Raised while booting, before the shell existed — and still toasted once
    // the shell mounted (issue #449).
    expect(find.textContaining('using the default device'), findsOneWidget);
    // … and the stored preference survives an unplugged interface (design §5).
    expect(settingsStore.saveCount, 0);
    expect(settings.value.audio.outputDevice, 'Unplugged Interface');

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
