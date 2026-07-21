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
import 'package:phi/surfaces/midi/clip_transport_row.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **record arm + capture flow** (issue #261), driven
/// through the real [PhiApp]: the transport row's record button arms record,
/// arm + play starts a take, MIDI-in fed through the [FakeMidiGateway] is
/// captured into the edited clip's source notes, and stop ends the take — the
/// full path button → EngineMidiController → RecordController → TakeRecorder →
/// the clip's undo scope → the source clip the piano roll and ghost read.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('arm record, play, and a played note lands in the clip', (
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

    // Open the MIDI surface — the seeded clip.phrase_a is the edited clip.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();

    final source = engine.midi.editedSession.chain.source;
    final before = source.notes.length;

    // ── Arm record via the transport row's record button ──────────────────────
    expect(find.byKey(ClipTransportRow.recordArmKey), findsOneWidget);
    await tester.tap(find.byKey(ClipTransportRow.recordArmKey));
    await tester.pump();
    expect(engine.midi.record.armed, isTrue);

    // ── Arm + play starts a take ──────────────────────────────────────────────
    await tester.tap(find.byKey(ClipTransportRow.playKey));
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.midi.record.isRecording, isTrue);

    // ── Play a note on the (fake) keyboard: note-on, let the beat advance, off ─
    midiGateway.emitNoteOn('Keystation 61', 67, 100);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    midiGateway.emitNoteOff('Keystation 61', 67);
    await tester.pump(const Duration(milliseconds: 20));

    // ── Stop ends the take and commits the pass ───────────────────────────────
    await tester.tap(find.byKey(ClipTransportRow.stopKey));
    await tester.pump();
    expect(engine.midi.record.isRecording, isFalse);

    // The played note is now a source note of the edited clip.
    expect(source.notes.length, before + 1);
    final captured = source.notes.last;
    expect(captured.pitch, 67.0);
    expect(captured.start, greaterThanOrEqualTo(0.0));
    expect(captured.duration, greaterThanOrEqualTo(0.0));

    // Undo peels the whole take in one step (a pass is one undo step).
    engine.midi.editedSession.editor.undo();
    expect(source.notes.length, before);

    // Arm survives the stop; a second click disarms.
    expect(engine.midi.record.armed, isTrue);
    await tester.tap(find.byKey(ClipTransportRow.recordArmKey));
    await tester.pump();
    expect(engine.midi.record.armed, isFalse);

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
