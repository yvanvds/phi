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
import 'package:phi/shell/bottom_status/audio_device_chip.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/settings/audio_settings_section.dart';
import 'package:phi/shell/settings/settings_dialog.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the status-bar audio-device chip (issue #271, design
/// `docs/design/diagnostics.md` §5) driven through the real [PhiApp]: the chip
/// walks ok → reconnecting → lost → ok as the fake gateway loses and regains a
/// device, each transition lands a paired log entry through the notice channel,
/// and clicking the chip opens the settings dialog's AUDIO section.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [44100.0, 48000.0],
  bufferSizes: [128, 256],
  defaultBufferSize: 256,
  outputLatency: 256,
);
const _beta = AudioDeviceDescriptor(
  name: 'Beta',
  hostName: 'ASIO',
  sampleRates: [48000.0, 96000.0],
  bufferSizes: [64, 128],
  defaultBufferSize: 64,
  outputLatency: 128,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the chip walks ok → reconnecting → lost → ok, logging each '
      'transition, and clicks through to settings AUDIO', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = FakeYseGateway()..devices = const [_alpha, _beta];
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    // Boot with a stored device so the coordinator opens it (initOffline +
    // openAudioDevice), giving a real live-device read-back — a healthy start.
    final settingsStore = FakeAppSettingsStore(
      const AppSettings(
        audio: AudioSettings(outputHost: 'WASAPI', outputDevice: 'Alpha'),
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

    // Fires the telemetry tick the monitor re-evaluates on, then lets the chip
    // rebuild off the health notifier.
    Future<void> tick() async {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
    }

    bool logged(String needle, LogLevel level) => notices.log.entries.any(
      (e) => e.text.contains(needle) && e.level == level,
    );

    // ── ok ──────────────────────────────────────────────────────────────────
    // Boot opened Alpha, so the chip reads healthy.
    await tick();
    expect(engine.activeAudioSettings.outputDevice, 'Alpha');
    expect(find.byKey(AudioDeviceChip.chipKey), findsOneWidget);
    expect(find.text('AUDIO'), findsOneWidget);

    // ── reconnecting ──────────────────────────────────────────────────────────
    // The device falls away with no loss notice — the auto-reconnect window.
    gateway.activeSampleRateValue = 0;
    await tick();
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(logged('reconnecting', LogLevel.warning), isTrue);

    // ── lost ────────────────────────────────────────────────────────────────
    // Every device vanishes; a switch attempt exhausts every fallback and the
    // engine raises `noAudioDevice`, so the chip reads a total loss.
    gateway.devices = const [];
    engine.switchAudioDevice(const AudioSettings());
    await tick();
    expect(find.text('NO AUDIO'), findsOneWidget);
    expect(logged('lost', LogLevel.error), isTrue);

    // ── ok (recovery) ─────────────────────────────────────────────────────────
    // The hardware comes back; the chip returns to healthy and recovery logs a
    // quiet info trace.
    gateway.devices = const [_alpha, _beta];
    gateway.activeSampleRateValue = 48000;
    await tick();
    expect(find.text('AUDIO'), findsOneWidget);
    expect(logged('recovered', LogLevel.info), isTrue);

    // ── click-through ─────────────────────────────────────────────────────────
    // Clicking the chip opens the settings dialog straight to its AUDIO section.
    await tester.tap(find.byKey(AudioDeviceChip.chipKey));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.byType(AudioSettingsSection), findsOneWidget);
    expect(find.text('OUTPUT DEVICE'), findsOneWidget);

    notices.dispose();
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
