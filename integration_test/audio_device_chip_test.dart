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
/// walks ok → reconnecting → ok → lost as the fake gateway loses and regains a
/// device, each transition lands a paired log entry through the notice channel,
/// and clicking the chip opens the settings dialog's AUDIO section.
///
/// Since issue #410 the recovery leg is the point of the test. It used to be
/// faked — the test assigned `gateway.activeSampleRateValue` and the chip
/// obligingly went green, modelling a recovery from a *closed* engine that
/// libyse cannot perform. Here nothing touches the live state: the hardware comes
/// back, Phi's own bounded supervisor re-opens a device through
/// `openAudioDevice`, and the stream that comes up is the engine's answer, not
/// the test's. The last leg then lets the budget run out with the hardware still
/// gone, which is the only thing that now reads as **NO AUDIO** — the state where
/// recovery really is the performer's move.
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
      // Four attempts 100 ms apart instead of the shipped eight over two
      // minutes: the *policy* is pinned in the unit tests, what this one needs
      // is a run short enough to watch both endings inside a widget test.
      audioRecoverySchedule: const [
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
        Duration(milliseconds: 300),
      ],
    );
    final session = SessionState();
    // Store a device so the app ends up on it, giving a real live-device
    // read-back — a healthy start. This walks the production sequence, and since
    // issue #405 the only one: `engine.start()` on the platform default, then
    // `switchAudioDevice(stored)` once the workstation has loaded settings
    // (`Workstation._startProject`). Since issue #403 the fake enumerates its
    // hardware on `init()` only, the way the engine does, so reaching 'Alpha'
    // here also proves the sequence never resolves a stored device against an
    // un-enumerated engine.
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
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(find.byKey(AudioDeviceChip.chipKey), findsOneWidget);
    expect(find.text('AUDIO'), findsOneWidget);

    // ── the loss, and Phi trying ────────────────────────────────────────────
    // The interface is pulled out of the machine. Note what is *not* here: no
    // `switchAudioDevice`, because an unplugged cable involves no switch —
    // reassigning the fake's hardware takes the open stream down with it, the
    // way PortAudio errors the stream out and libyse closes it. Phi notices on
    // its telemetry tick and arms a bounded run, so the chip reads RECONNECTING
    // (issue #410): nothing is open, but something is trying.
    gateway.devices = const [];
    await tick();
    expect(engine.activeAudioState().sampleRate, 0);
    expect(engine.activeAudioSettings, isNull);
    expect(engine.audioRecovery.retrying, isTrue);
    expect(find.text('RECONNECTING'), findsOneWidget);
    expect(logged('reconnecting', LogLevel.warning), isTrue);
    // NO AUDIO is held back for the state where nothing is trying any more.
    expect(logged('lost', LogLevel.error), isFalse);

    // ── ok (a real recovery) ────────────────────────────────────────────────
    // The interface is plugged back in. Nothing here touches the live state —
    // the next scheduled attempt calls `openAudioDevice` through the gateway and
    // a stream genuinely comes up, which is what turns the chip green. This is
    // the leg that used to be faked by assigning `activeSampleRateValue`.
    gateway.devices = const [_alpha, _beta];
    await tester.pump(const Duration(milliseconds: 600));
    await tick();

    expect(engine.activeAudioState().sampleRate, greaterThan(0));
    // And it came back on *Alpha*, the device the performer stored — recovery
    // reaches for what was asked for before it settles for anything else.
    expect(engine.activeAudioSettings?.outputDevice, 'Alpha');
    expect(engine.audioRecovery.retrying, isFalse);
    expect(find.text('AUDIO'), findsOneWidget);
    expect(logged('recovered', LogLevel.info), isTrue);

    // ── lost (the budget runs out) ──────────────────────────────────────────
    // This time the hardware stays gone. Phi tries its four attempts, gives up,
    // and says so — and only then does the chip read NO AUDIO, which now carries
    // exactly one meaning: recovery is manual from here.
    gateway.devices = const [];
    await tick();
    expect(find.text('RECONNECTING'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1800));
    await tick();

    expect(engine.audioRecovery.gaveUp, isTrue);
    expect(engine.audioRecovery.attempts, 4);
    expect(find.text('NO AUDIO'), findsOneWidget);
    expect(logged('lost', LogLevel.error), isTrue);
    // The give-up says how hard it tried and where to go next.
    expect(logged('4 attempts', LogLevel.error), isTrue);
    expect(logged('Settings', LogLevel.error), isTrue);

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
