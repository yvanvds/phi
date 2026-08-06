import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/app_settings/audio_settings.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/diagnostics/notice_center.dart';
import 'package:phi/shell/settings/settings_dialog.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that a **total audio-device loss** tells the truth
/// everywhere a performer can look (issue #408), driven through the real
/// [PhiApp]: the status chip reads NO AUDIO, the settings DIAGNOSTICS row names
/// no device rather than the interface the engine is no longer on, and the block
/// the copy button puts on the clipboard — the one that gets pasted into a bug
/// report — says the same.
///
/// The loss is provoked the way a performer meets it: they pick another output
/// in the AUDIO section while their current interface is being unplugged. The
/// engine closes the running device to try the new one, the new one refuses, and
/// the revert finds the old one gone. Before #408 `AudioDeviceCoordinator.current`
/// kept naming that old device, so the diagnostics read "Alpha · WASAPI" beside a
/// live rate of 0.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [48000.0],
  bufferSizes: [256],
  defaultBufferSize: 256,
  outputLatency: 256,
);
const _beta = AudioDeviceDescriptor(
  name: 'Beta',
  hostName: 'ASIO',
  sampleRates: [48000.0],
  bufferSizes: [128],
  defaultBufferSize: 128,
  outputLatency: 128,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a total device loss reads as "no device" in the chip, the '
      'DIAGNOSTICS row, and the pasted report', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = FakeYseGateway()
      ..devices = const [_alpha, _beta]
      ..engineVersionValue = 'yse-e2e 4.0.8';
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
      // A two-attempt run 50 ms apart: this test is about what the surfaces say
      // once recovery has *finished*, so the budget is spent almost immediately
      // and the readings settle on the manual-recovery state (issue #410).
      audioRecoverySchedule: const [
        Duration(milliseconds: 50),
        Duration(milliseconds: 50),
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

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

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

    /// Fires the telemetry tick the health monitor re-evaluates on, then lets
    /// the chip rebuild off the health notifier.
    Future<void> tick() async {
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
    }

    Finder sectionTile(String label) => find.descendant(
      of: find.byType(SettingsDialog),
      matching: find.text(label),
    );

    // ── a healthy start ─────────────────────────────────────────────────────
    await tick();
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(find.text('AUDIO'), findsOneWidget);

    // Open Settings from the File menu, landing on the AUDIO section.
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings…'));
    await tester.pumpAndSettle();
    expect(find.text('OUTPUT DEVICE'), findsOneWidget);

    // ── the loss ────────────────────────────────────────────────────────────
    // Beta refuses to open, and Alpha is pulled out of the machine while the
    // performer is choosing. The engine closes Alpha to try Beta, Beta fails,
    // and the revert has nothing left to reopen.
    gateway.unopenableDeviceNames.add('Beta');
    gateway.devices = const [_beta];

    await tester.tap(find.byType(PhiSelect<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').last);
    await tester.pumpAndSettle();

    // Nothing is open, and nothing was persisted — the stored preference still
    // names the interface the performer chose (design §5).
    expect(engine.activeAudioSettings, isNull);
    expect(engine.activeAudioState().sampleRate, 0);
    expect(settings.value.audio.outputDevice, 'Alpha');
    expect(settingsStore.saveCount, 0);

    // Phi retried on its own (issue #410) and, with both devices still gone,
    // ran out of attempts — which is what makes the readings below the *final*
    // word rather than a snapshot of something still in flight.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(engine.audioRecovery.gaveUp, isTrue);

    // ── the DIAGNOSTICS row ─────────────────────────────────────────────────
    await tester.tap(sectionTile('DIAGNOSTICS'));
    await tester.pumpAndSettle();
    expect(find.textContaining('yse-e2e 4.0.8'), findsOneWidget);
    expect(find.text('ACTIVE DEVICE'), findsOneWidget);
    expect(find.textContaining('none — no audio device open'), findsOneWidget);
    // The lie this issue is about: the row must not name the device that went
    // away, nor claim the platform default is carrying the audio.
    expect(find.textContaining('Alpha · WASAPI'), findsNothing);
    expect(find.textContaining('System default'), findsNothing);
    // …and it records that Phi tried and stopped (issue #410), so the row
    // answers the next question a reader has: is this still going to fix itself?
    expect(find.textContaining('gave up after 2 attempts'), findsOneWidget);

    // ── the pasted report ───────────────────────────────────────────────────
    await tester.tap(find.text('copy for bug report'));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);
    expect(copied, contains('Active device: none — no audio device open'));
    expect(copied, contains('Active state: no device open'));
    expect(copied, isNot(contains('Alpha · WASAPI')));

    // ── the status chip ─────────────────────────────────────────────────────
    await tester.tap(
      find.descendant(
        of: find.byType(SettingsDialog),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    await tick();
    expect(find.text('NO AUDIO'), findsOneWidget);

    notices.dispose();
    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
