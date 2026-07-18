import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
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

/// End-to-end proof of clip persistence (issue #135) driven through the real
/// [PhiApp]: a fresh project seeds the demo clip with its transform chain, the
/// performer edits a note and toggles a chip, saves — and a second launch pointed
/// at the same project restores the *edited* clip **and** its interpretation (the
/// chain), not the seeded original. All against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final clipAddress = EntityAddress.parse('clip.phrase_a');

  ClipDocument clipDocumentOf(ProjectController controller) =>
      ClipDocument.fromJson(
        (controller.registry.entityAt(clipAddress)!.payload! as Map).cast(),
      );

  testWidgets('an edited clip + its chain round-trip a save/reload', (
    tester,
  ) async {
    const dir = '/projects/clip_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: seed, edit a note, toggle a chip, save --------------------
    final gateway1 = FakeYseGateway();
    final midi1 = FakeMidiGateway();
    final engine1 = PhiEngine(
      gateway1,
      midiGateway: midi1,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session1 = SessionState();
    final appSettings1 = AppSettingsController(settings);
    final controller1 = ProjectController(
      session: session1,
      settings: appSettings1,
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

    // A fresh project seeded the demo clip with its default chain.
    expect(clipDocumentOf(controller1).chain, isNotEmpty);
    expect(controller1.isDirty.value, isFalse);

    // Edit the live clip: add a distinctive note and toggle the first chip.
    final notesBefore = clipDocumentOf(controller1).source.notes.length;
    final firstActiveBefore = engine1.midi.chain.transforms.first.active;
    engine1.midi.editor.addNote(
      const MidiNote(pitch: 61, start: 0, duration: 1, velocity: 0.42),
    );
    engine1.midi.chain.setActiveAt(0, !firstActiveBefore);
    await tester.pump();

    // The edit dirtied the project and updated the clip entity in the registry.
    expect(controller1.isDirty.value, isTrue);
    final edited = clipDocumentOf(controller1);
    expect(edited.source.notes, hasLength(notesBefore + 1));
    expect(edited.source.notes.any((n) => n.pitch == 61), isTrue);
    expect(edited.chain.first.active, !firstActiveBefore);

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

    // --- Launch 2: reopen, expect the edited clip + chain restored -----------
    final gateway2 = FakeYseGateway();
    final midi2 = FakeMidiGateway();
    final engine2 = PhiEngine(
      gateway2,
      midiGateway: midi2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
    // A fresh owner over the same store — a "restart" reading the saved recents,
    // which auto-restores the saved project.
    final appSettings2 = AppSettingsController(settings);
    final controller2 = ProjectController(
      session: session2,
      settings: appSettings2,
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
    appSettings1.dispose();
    session1.dispose();

    // The restored clip carries the added note and the toggled chip state — the
    // edits, not the seeded original.
    final restored = clipDocumentOf(controller2);
    expect(restored.source.notes.any((n) => n.pitch == 61), isTrue);
    expect(restored.chain, isNotEmpty);
    expect(restored.chain.first.active, !firstActiveBefore);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
