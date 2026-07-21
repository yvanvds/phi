import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/top_toolbar/metronome_control.dart';
import 'package:phi/shell/top_toolbar/metronome_popover.dart';
import 'package:phi/surfaces/midi/clip_transport_row.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of **count-in** (issue #263), driven through the real
/// [PhiApp]: the toolbar metronome popover's count-in picker sets the count
/// length, and pressing the transport row's play button then *waits* — the
/// edited session does not start and an armed take is deferred while the count
/// runs — until a stop aborts it cleanly. The full path popover →
/// CountInController and play button → ClipLibraryController →
/// EngineMidiController.play → count-in gate.
///
/// The count *completing* on the downbeat is a timing behaviour, verified
/// deterministically against a fake engine clock in the `EngineMidiController`
/// count-in tests (the issue's "fake-clock tests"); here we prove the visible
/// gating + abort the real widgets drive, without leaning on wall-clock elapse.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('a count-in delays play and record until aborted by stop', (
    tester,
  ) async {
    final midiGateway = FakeMidiGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      midiGateway: midiGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seedDefaultProject,
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

    // Open the MIDI surface — the seeded clip is the edited clip.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    // ── Set a 2-bar count-in from the toolbar metronome popover ────────────────
    await tester.tap(find.byKey(MetronomeControl.popoverButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MetronomePopover.countInKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 bars'));
    await tester.pumpAndSettle();
    expect(engine.midi.countIn.bars, 2);
    // Dismiss the popover so the transport row is clickable.
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();

    // ── Arm record, then press play ────────────────────────────────────────────
    await tester.tap(find.byKey(ClipTransportRow.recordArmKey));
    await tester.pump();
    expect(engine.midi.record.armed, isTrue);

    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump();

    // The count is running: the session has NOT started, and the take is
    // deferred to the downbeat (design §5).
    expect(engine.midi.countIn.isCounting, isTrue);
    expect(engine.midi.isPlaying, isFalse);
    expect(engine.midi.record.isRecording, isFalse);

    // ── Stop during the count aborts it cleanly ────────────────────────────────
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(engine.midi.countIn.isCounting, isFalse);
    expect(engine.midi.isPlaying, isFalse);
    // The arm survives the abort — only the take start was cancelled.
    expect(engine.midi.record.armed, isTrue);

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
