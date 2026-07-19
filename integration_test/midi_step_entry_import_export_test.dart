import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/smf/smf_reader.dart';
import 'package:phi/domain/midi/smf/smf_writer.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/midi/library/library_panel.dart';
import 'package:phi/surfaces/midi/piano_roll_editor.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/midi/fake_midi_file_io.dart';

/// End-to-end proof of the piano-roll **caret step entry** and the polished
/// **import / export flow** (issue #191), driven through the real [PhiApp]:
///
/// - focusing the roll and pressing arrow keys + `Enter` authors a note in the
///   edited clip at the caret's lane/beat (step entry);
/// - the header IMPORT lands the picked `.mid` as a **new** clip entity in the
///   selected group, slugged from its filename, and opens it — never
///   overwriting the open clip (design §3);
/// - the header EXPORT writes the **selected** clip's transformed output, named
///   from its address leaf, round-tripping through the SMF codec.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  final phraseA = EntityAddress.parse('clip.phrase_a');
  final importedClip = EntityAddress.parse('clip.drum_loop');

  List<MidiNote> sortNotes(List<MidiNote> notes) =>
      List<MidiNote>.of(notes)..sort((a, b) {
        if (a.start != b.start) return a.start.compareTo(b.start);
        return a.pitch.compareTo(b.pitch);
      });

  testWidgets('caret step entry authors a note; import-as-new + export-selected', (
    tester,
  ) async {
    // A 3-note clip on a 1/16 grid with 1/127 velocities, so it round-trips SMF
    // byte-exact (the same shape the #30 import/export test used).
    final smf = const SmfWriter().write(
      MidiClip(
        bars: 2,
        notes: const [
          MidiNote(pitch: 62, start: 0.0, duration: 0.5, velocity: 100 / 127),
          MidiNote(pitch: 65, start: 1.0, duration: 0.25, velocity: 64 / 127),
          MidiNote(pitch: 69, start: 2.0, duration: 1.0, velocity: 120 / 127),
        ],
      ),
    );
    final fakeIo = FakeMidiFileIo(openBytes: smf, openName: 'Drum Loop.mid');

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
        midiFileIo: fakeIo,
      ),
    );
    await tester.pumpAndSettle();

    // Open the MIDI surface, expand the library, and select the seeded clip so
    // it is the edited (selected) clip — the import's target group is its group.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.rowKey(phraseA)));
    await tester.pumpAndSettle();
    expect(engine.midi.editedSession.address, phraseA);

    // ── Caret step entry ──────────────────────────────────────────────────────
    // Focus the roll with a tap (it authors a throwaway note and selects it),
    // then Escape to clear the selection so the arrows drive the step-entry
    // caret rather than nudging the selected note.
    final rollRect = tester.getRect(find.byType(PianoRollEditor));
    await tester.tapAt(rollRect.center);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    final before = engine.midi.editedSession.chain.source.notes.length;
    // Arrow keys summon + move the caret; Enter drops a grid-length note there.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // Exactly one note was authored into the edited clip's source by the caret.
    expect(engine.midi.editedSession.chain.source.notes.length, before + 1);

    // ── Import as a new entity in the selected group ─────────────────────────
    await tester.tap(find.text('IMPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.openCalls, 1);

    // A new clip landed in the registry, slugged from the filename — the open
    // clip.phrase_a was NOT overwritten (still 10 + 1 stepped note).
    expect(controller.registry.contains(importedClip), isTrue);
    expect(engine.midi.editedSession.address, importedClip);
    expect(engine.midi.editedSession.chain.source.notes, hasLength(3));
    // phrase_a is untouched by the import.
    expect(controller.registry.contains(phraseA), isTrue);

    // The header follows the newly opened clip.
    expect(find.text('MIDI · DRUM_LOOP'), findsOneWidget);

    // ── Export the selected clip's transformed output ────────────────────────
    // drum_loop is the selected (edited) clip and is un-edited; exporting it
    // writes its transformed output, named from its leaf.
    await tester.tap(find.text('EXPORT'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalls, 1);
    expect(fakeIo.savedName, 'drum_loop.mid');
    expect(fakeIo.savedBytes, isNotNull);

    final decoded = const SmfReader().read(fakeIo.savedBytes!);
    expect(
      sortNotes(decoded.notes),
      sortNotes(engine.midi.editedSession.chain.output),
    );

    await engine.dispose();
    await midiGateway.dispose();
    controller.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
