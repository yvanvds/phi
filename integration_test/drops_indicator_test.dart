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
import 'package:phi/shell/bottom_status/status_chip.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the `DROPS` indicator (issue #350), driven through the
/// real [PhiApp]: the whole path from the gateway's raw device-stall gauge,
/// through the engine's telemetry tick and `AudioStallTracker`, to the chip the
/// performer actually reads in the bottom strip.
///
/// The bug was that the chip rendered the engine's gauge directly. That gauge
/// counts *consecutive control ticks with no audio callback*, so at Phi's 16 ms
/// tick a healthy device pushes it to `1` roughly once a second — and the chip
/// flickered to `1` at idle. This test drives exactly that pattern and requires
/// the chip to stay at `0`, then requires a genuine sustained stall to count
/// once, and only once.
///
/// A 2048-frame device is used deliberately: its callback period (≈42.7 ms) is
/// far longer than the control tick, so the stall threshold is *derived* (6
/// ticks) rather than the floor — a gauge of `4` there is a normal
/// inter-callback gap, not a dropout.
const _alpha = AudioDeviceDescriptor(
  name: 'Alpha',
  hostName: 'WASAPI',
  sampleRates: [48000.0],
  bufferSizes: [2048],
  defaultBufferSize: 2048,
  outputLatency: 2048,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DROPS ignores the idle stall-gauge flicker and counts only '
      'real stalls, once each', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = FakeYseGateway()..devices = const [_alpha];
    final engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    // Boot with a stored device so the coordinator opens it — the chip's
    // threshold is derived from the *live* rate + buffer, so a real open matters.
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

    // Drives one telemetry tick with the gauge reading [gauge], then lets the
    // status strip rebuild off it.
    Future<void> tick(int gauge) async {
      gateway.deviceStallTicksValue = gauge;
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      await tester.pump();
    }

    String drops() => tester
        .widgetList<StatusChip>(find.byType(StatusChip))
        .firstWhere((chip) => chip.label == 'DROPS')
        .value;

    // The device really did open, so the threshold is derived from 2048 frames
    // @ 48 kHz rather than the no-device floor.
    expect(engine.activeAudioState().bufferSize, 2048);
    expect(find.text('DROPS'), findsOneWidget);
    expect(drops(), '0');

    // ── the idle flicker (the reported bug) ─────────────────────────────────
    // A healthy device: the gauge blips to 1 whenever a control tick lands
    // between two callbacks, and clears on the next. None of this is a dropout,
    // so the chip must not move. Pre-fix, each `1` rendered as `DROPS 1`.
    for (final gauge in [1, 0, 0, 1, 0, 1, 1, 0]) {
      await tick(gauge);
      expect(drops(), '0', reason: 'gauge $gauge is not a dropout');
    }

    // ── a gap that is long, but still normal for this buffer ────────────────
    // Four empty ticks (~64 ms) is under twice the 42.7 ms callback period, so
    // it stays below the derived threshold and still counts for nothing.
    await tick(4);
    expect(drops(), '0');
    await tick(0);

    // ── a real stall ────────────────────────────────────────────────────────
    // Nine empty ticks (~144 ms of silence) is well past what this device could
    // legitimately be quiet for: one dropout.
    await tick(9);
    expect(drops(), '1');

    // ── it stays one while it persists ──────────────────────────────────────
    // The count latches on the leading edge, so a stall that deepens and drags
    // on is still the same single event — not one per telemetry tick.
    await tick(14);
    await tick(22);
    await tick(31);
    expect(drops(), '1');

    // ── recovery re-arms, and the next stall counts again ───────────────────
    await tick(0);
    await tick(1); // back to the healthy flicker
    expect(drops(), '1');
    await tick(12);
    expect(drops(), '2');

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
    await gateway.dispose();
  });
}
