import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/bottom_status/audio_device_chip.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that an audio interface plugged in **after** Phi started is
/// picked up without a restart (issue #445), driven through the real [PhiApp].
///
/// Under libYSE 2.4 the engine's device list was frozen at the first `init()`
/// (issue #412), so a launch with nothing plugged in said "restart Phi" and the
/// chip sat on NO AUDIO for the rest of the session. yse 0.2.0's
/// `refreshDevices()` reads the machine afresh whenever nothing is open, and
/// every recovery attempt now starts with one — so the launch reads
/// RECONNECTING, and the stored interface is opened the moment it arrives.
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

  testWidgets('a launch with no audio hardware reconnects onto the stored '
      'interface once it is plugged in — no restart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Nothing is plugged in at launch.
    final gateway = FakeYseGateway()..devices = const [];
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
      audioRecoverySchedule: const [
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
      ],
    );
    final session = SessionState();
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
    await tester.pump(const Duration(milliseconds: 100));

    Future<void> tick() async {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
    }

    // ── launch: nothing open, but Phi is trying ─────────────────────────────
    await tick();
    expect(engine.activeAudioState().sampleRate, 0);
    expect(engine.activeAudioSettings, isNull);
    expect(engine.audioRecovery.retrying, isTrue);
    expect(find.byKey(AudioDeviceChip.chipKey), findsOneWidget);
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(
      notices.log.entries.any((e) => e.text.contains('restart Phi')),
      isFalse,
      reason: 'an empty device list is no longer a restart-level fact',
    );

    // ── the interface arrives ───────────────────────────────────────────────
    // Nothing here touches the live state: the next attempt refreshes the
    // device list, finds Alpha by name + host, and opens it.
    gateway.devices = const [_beta, _alpha];
    await tester.pump(const Duration(milliseconds: 400));
    await tick();

    expect(engine.activeAudioState().sampleRate, greaterThan(0));
    // The stored device, not whatever the platform default (Beta) would be.
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(engine.audioRecovery.retrying, isFalse);
    expect(find.text('AUDIO'), findsOneWidget);
    // And the settings window's list now offers what arrived.
    expect(
      engine.audioDevices().map((d) => d.name),
      containsAll(<String>['Alpha', 'Beta']),
    );

    notices.dispose();
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
