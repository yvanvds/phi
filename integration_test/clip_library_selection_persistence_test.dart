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
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/midi/library/library_panel.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that a **library-selected** clip's edits persist (issue
/// #197), driven through the real [PhiApp]: a fresh project seeds `clip.phrase_a`
/// (the boot clip). Through the library panel the performer adds a second clip,
/// selects the seeded one and then the new one — swapping the edited session each
/// time — edits a note on the newly selected clip, and saves. A second launch
/// pointed at the same project restores the edit **into that clip's entity**, not
/// the boot/seed. Before this fix the publisher stayed bound to the boot session,
/// so only edits to the first clip round-tripped. All against in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final phraseA = EntityAddress.parse('clip.phrase_a');
  final newClip = EntityAddress.parse('clip.clip');

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  ClipDocument clipDoc(ProjectController controller, EntityAddress address) {
    final payload = controller.registry.entityAt(address)!.payload;
    if (payload is ClipDocument) return payload;
    return ClipDocument.fromJson((payload! as Map).cast());
  }

  testWidgets('a non-boot clip selected in the panel persists its edit', (
    tester,
  ) async {
    const dir = '/projects/selection_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: add a clip, select it, edit a note, save ------------------
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

    // Open the MIDI surface and expand the (collapsed-by-default) library panel.
    await tester.tap(railFor(SurfaceId.midi));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();

    // Add a second clip through the header menu — it lands in the registry and
    // becomes the edited session.
    await tester.tap(find.byKey(LibraryPanel.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new clip'));
    await tester.pumpAndSettle();
    expect(controller1.registry.contains(newClip), isTrue);
    expect(engine1.midi.editedSession.address, newClip);

    // Swap the editor to the seeded clip, then back to the new one — the panel
    // selection seam the publisher must follow (issue #197).
    await tester.tap(find.byKey(LibraryPanel.rowKey(phraseA)));
    await tester.pumpAndSettle();
    expect(engine1.midi.editedSession.address, phraseA);
    await tester.tap(find.byKey(LibraryPanel.rowKey(newClip)));
    await tester.pumpAndSettle();
    expect(engine1.midi.editedSession.address, newClip);

    // The new clip started empty; edit a note on it (the edited session's editor).
    final phraseANotes = clipDoc(controller1, phraseA).source.notes.length;
    expect(clipDoc(controller1, newClip).source.notes, isEmpty);
    engine1.midi.editor.addNote(
      const MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5),
    );
    await tester.pump();

    // The edit dirtied the project and updated *the selected clip's* entity —
    // the seeded boot clip is untouched.
    expect(controller1.isDirty.value, isTrue);
    expect(clipDoc(controller1, newClip).source.notes, hasLength(1));
    expect(clipDoc(controller1, phraseA).source.notes, hasLength(phraseANotes));

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

    // --- Launch 2: reopen, expect the selected clip's edit restored ----------
    final gateway2 = FakeYseGateway();
    final midi2 = FakeMidiGateway();
    final engine2 = PhiEngine(
      gateway2,
      midiGateway: midi2,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session2 = SessionState();
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

    // The restored non-boot clip carries the edit; the boot clip is unchanged.
    expect(clipDoc(controller2, newClip).source.notes, hasLength(1));
    expect(clipDoc(controller2, phraseA).source.notes, hasLength(phraseANotes));

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
