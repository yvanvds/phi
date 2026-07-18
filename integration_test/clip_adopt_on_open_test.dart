import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/project/project_menu.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of issue #139 driven through the real [PhiApp]: #135 made a
/// clip's edits round-trip at the **registry** level; this proves the follow-up
/// — on reopening a saved project the **live** engine clip (its chain / editor)
/// reflects the edit, not the boot default ([defaultDemoChain]).
///
/// The distinction matters: the sibling `clip_persistence` test asserts the
/// registry payload; here we assert `engine.midi.chain`, the objects the MIDI
/// surface actually plays and paints. All against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reopening a project adopts the edited clip into the live engine', (
    tester,
  ) async {
    const dir = '/projects/adopt_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: seed, edit the live clip, save ----------------------------
    final gateway1 = FakeYseGateway();
    final midi1 = FakeMidiGateway();
    final engine1 = PhiEngine(
      gateway1,
      midiGateway: midi1,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final controller1 = ProjectController(
      session: session1,
      settingsStore: settings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        key: const ValueKey('launch-1'),
        engine: engine1,
        session: session1,
        projectController: controller1,
        directoryPicker: FakeProjectDirectoryPicker(newLocationPath: dir),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // A fresh project seeded the demo clip; edit it on the live engine objects.
    final firstActiveBefore = engine1.midi.chain.transforms.first.active;
    final notesBefore = engine1.midi.chain.source.notes.length;
    expect(
      engine1.midi.chain.source.notes.any((n) => n.pitch == 61),
      isFalse,
      reason: 'the demo clip has no pitch 61 — our edit is distinctive',
    );
    engine1.midi.editor.addNote(
      const MidiNote(pitch: 61, start: 0, duration: 1, velocity: 0.42),
    );
    engine1.midi.chain.setActiveAt(0, !firstActiveBefore);
    await tester.pump();

    // Save via the project menu; the new project gets its home from the picker.
    await tester.tap(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('untitled'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller1.isDirty.value, isFalse);

    // --- Launch 2: reopen; the LIVE engine clip must carry the edit ----------
    final gateway2 = FakeYseGateway();
    final midi2 = FakeMidiGateway();
    final engine2 = PhiEngine(
      gateway2,
      midiGateway: midi2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    final controller2 = ProjectController(
      session: session2,
      settingsStore: settings, // same recents → auto-restores the saved project
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
      seedRegistry: seedDefaultProject,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        key: const ValueKey('launch-2'),
        engine: engine2,
        session: session2,
        projectController: controller2,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();

    // Release launch 1.
    await engine1.dispose();
    await gateway1.dispose();
    controller1.dispose();
    session1.dispose();

    // The live engine chain — not just the registry payload — reflects the
    // edit: the added note is present and the toggled chip kept its state.
    final liveNotes = engine2.midi.chain.source.notes;
    expect(liveNotes, hasLength(notesBefore + 1));
    expect(liveNotes.any((n) => n.pitch == 61), isTrue);
    expect(engine2.midi.chain.transforms.first.active, !firstActiveBefore);
    // Reopening did not spuriously re-dirty the project.
    expect(controller2.isDirty.value, isFalse);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    session2.dispose();
  });
}
