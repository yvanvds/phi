import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/code/code_script.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/shell/project/project_menu.dart';
import 'package:phi/surfaces/code/code_library_panel.dart';
import 'package:re_editor/re_editor.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the script **library panel** + `code.` entities (issue
/// #235) driven through the real [PhiApp]: a fresh project seeds `code.scratch`,
/// so opening the Code surface and expanding the panel shows it. From there a new
/// script is added (and becomes the open script — the editor swaps to it), an
/// edit is typed into it and journaled per idle pause (dirtying the project), and
/// a save + second launch restores the edited source **byte-identical** — while
/// selection swaps the editor content between the two scripts. All against
/// in-memory fakes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final scratch = EntityAddress.parse('code.scratch');
  final newScript = EntityAddress.parse('code.script');
  const edited = 'note(60)\n# edited live\n';

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  CodeLineEditingController editor(WidgetTester tester) {
    final CodeEditor codeEditor = tester.widget(find.byType(CodeEditor));
    return codeEditor.controller!;
  }

  String sourceOf(ProjectRegistry registry, EntityAddress address) {
    final payload = registry.entityAt(address)!.payload;
    if (payload is CodeScript) return payload.source;
    return CodeScript.fromJson((payload! as Map).cast()).source;
  }

  testWidgets('scratch shows, add + edit persists byte-identical, swap works', (
    tester,
  ) async {
    const dir = '/projects/code_set.phi';
    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    final journal = FakeJournalStore();
    final settings = FakeAppSettingsStore();

    // --- Launch 1: open Code, add a script, edit it, save --------------------
    final gateway1 = FakeYseGateway();
    final engine1 = PhiEngine(
      gateway1,
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

    // Open the Code surface and expand the (collapsed-by-default) script panel.
    await tester.tap(railFor(SurfaceId.code));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CodeLibraryPanel.expandToggleKey));
    await tester.pumpAndSettle();

    // The seeded scratch script appears and is the open script — the editor
    // shows its seed content.
    expect(find.byKey(CodeLibraryPanel.rowKey(scratch)), findsOneWidget);
    expect(editor(tester).text, contains('scratchpad'));

    // Add a new script through the header + menu — it lands in the registry and
    // becomes the open (edited) script; the editor swaps to it (empty).
    await tester.tap(find.byKey(CodeLibraryPanel.addMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new script'));
    await tester.pumpAndSettle();
    expect(controller1.registry.contains(newScript), isTrue);
    expect(editor(tester).text, isEmpty);

    // Type into the new script; the edit journals after the idle pause, dirtying
    // the project and updating *that* script's entity (not the scratch).
    editor(tester).text = edited;
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller1.isDirty.value, isTrue);
    expect(sourceOf(controller1.registry, newScript), edited);
    expect(sourceOf(controller1.registry, scratch), contains('scratchpad'));

    // Selection swaps the editor content: scratch, then back to the new script.
    await tester.tap(find.byKey(CodeLibraryPanel.rowKey(scratch)));
    await tester.pumpAndSettle();
    expect(editor(tester).text, contains('scratchpad'));
    await tester.tap(find.byKey(CodeLibraryPanel.rowKey(newScript)));
    await tester.pumpAndSettle();
    expect(editor(tester).text, edited);

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

    // --- Launch 2: reopen, expect the edited script restored verbatim --------
    final gateway2 = FakeYseGateway();
    final engine2 = PhiEngine(
      gateway2,
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

    // The reopened project restored the edited script byte-identical, and the
    // untouched scratch script survived alongside it.
    expect(controller2.registry.contains(newScript), isTrue);
    expect(sourceOf(controller2.registry, newScript), edited);
    expect(controller2.registry.contains(scratch), isTrue);

    await engine2.dispose();
    await gateway2.dispose();
    controller2.dispose();
    appSettings2.dispose();
    session2.dispose();
  });
}
