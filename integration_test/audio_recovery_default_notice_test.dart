import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the recovery-settled-on-the-default notice (issue #413,
/// design `docs/design/settings-and-devices.md` §5), driven through the real
/// [PhiApp]: the performer's interface is pulled mid-set, Phi's bounded
/// recovery run (issue #410) fails to reopen it and settles for the platform
/// default — and the shell *says so*. The chip going back to green is exactly
/// the problem this notice exists for: without it, a set finishes on the
/// built-in speakers under a healthy-looking status bar, because recovery
/// stands down at the settle and nothing keeps watching for the preferred
/// interface. The stored preference must survive untouched, so re-picking the
/// device is one click once it returns.
const _builtin = AudioDeviceDescriptor(
  name: 'Built-in Output',
  hostName: 'WASAPI',
  sampleRates: [44100.0, 48000.0],
  bufferSizes: [256, 512],
  defaultBufferSize: 512,
  outputLatency: 512,
);
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'ASIO',
  sampleRates: [48000.0, 96000.0],
  bufferSizes: [64, 128],
  defaultBufferSize: 64,
  outputLatency: 128,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recovery that settles for the platform default announces the '
      'substitution and keeps the stored preference', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The built-in output is first, so it is what the platform default
    // resolves to — the settle has to land on a *different* device than the
    // stored one for the notice to have anything to announce.
    final gateway = FakeYseGateway()..devices = const [_builtin, _alpha];
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
      // Two quick attempts instead of the shipped eight over two minutes: the
      // cadence is pinned in the unit tests, this run only needs to reach the
      // settle inside a widget test.
      audioRecoverySchedule: const [
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
      ],
    );
    final session = SessionState();
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(outputHost: 'ASIO', outputDevice: 'Alpha'),
      ),
    );
    final settings = AppSettingsController(settingsStore);
    final controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => FakeProjectStore(),
      journalStoreFactory: (_) => FakeJournalStore(),
      autosaveIntervalOverride: const Duration(hours: 1),
    );
    final notices = NoticeCenter.build();

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
        noticeCenter: notices,
      ),
    );
    await tester.pumpAndSettle();

    // Fires the telemetry tick the device-loss watch runs on, then lets the
    // chip rebuild off the health notifier.
    Future<void> tick() async {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
    }

    bool logged(String needle, LogLevel level) => notices.log.entries.any(
      (e) => e.text.contains(needle) && e.level == level,
    );

    // ── the healthy start ───────────────────────────────────────────────────
    // Boot opened the platform default, then the stored preference moved the
    // engine onto Alpha — the production launch sequence (design §5).
    await tick();
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(find.text('AUDIO'), findsOneWidget);

    // ── Alpha is pulled, and only Alpha ─────────────────────────────────────
    // The built-in output stays in the machine. Phi notices the loss on its
    // telemetry tick and arms the bounded run, so the chip reads RECONNECTING.
    gateway.devices = const [_builtin];
    await tick();
    expect(engine.activeAudioSettings, isNull);
    expect(engine.audioRecovery.retrying, isTrue);
    expect(find.text('RECONNECTING'), findsOneWidget);

    // ── the settle ──────────────────────────────────────────────────────────
    // The first attempt reaches for Alpha (still gone), then settles for the
    // platform default — audio matters more than the preference. The chip goes
    // green again, which is precisely why the substitution must be said out
    // loud: this green is not the green the performer thinks it is.
    await tester.pump(const Duration(milliseconds: 600));
    await tick();

    expect(engine.activeAudioState().sampleRate, greaterThan(0));
    expect(engine.activeAudioSettings, isNotNull);
    expect(engine.activeAudioSettings?.outputDevice, isNull); // the default
    expect(engine.audioRecovery.retrying, isFalse);
    expect(find.text('AUDIO'), findsOneWidget);

    // The one-off notice landed through the notice channel at warning level
    // (issue #413): it names the device that is still missing and points at
    // the way back.
    expect(logged('default device', LogLevel.warning), isTrue);
    expect(logged('"Alpha"', LogLevel.warning), isTrue);
    expect(logged('Settings', LogLevel.warning), isTrue);

    // And the stored preference survived the whole episode untouched — the
    // coordinator never writes it, so going back to Alpha is one click in
    // Settings › Audio once the interface returns.
    expect(settings.value.audio.outputDevice, 'Alpha');
    expect(settings.value.audio.outputHost, 'ASIO');

    notices.dispose();
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
