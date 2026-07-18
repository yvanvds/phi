import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/project/project_menu.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the project lifecycle UI (issue #123) driven through the
/// real [PhiApp]: the toolbar project menu, the dirty indicator, save, and the
/// launch-time crash-recovery prompt — all against in-memory fakes so no native
/// dialog or filesystem is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('menu save clears the dirty indicator end to end', (
    tester,
  ) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final store = FakeProjectStore();
    final settings = AppSettingsController(FakeAppSettingsStore());
    final controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => FakeJournalStore(),
      autosaveIntervalOverride: const Duration(hours: 1),
    );
    final picker = FakeProjectDirectoryPicker(
      newLocationPath: '/projects/live_set.phi',
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: controller,
        directoryPicker: picker,
      ),
    );
    await tester.pumpAndSettle();

    // The toolbar shows the project menu (untitled) and no dirty dot yet. Scope
    // to the menu — the scene name defaults to "untitled" too.
    final menuTrigger = find.descendant(
      of: find.byType(ProjectMenu),
      matching: find.text('untitled'),
    );
    expect(menuTrigger, findsOneWidget);
    expect(find.byTooltip('unsaved changes'), findsNothing);

    // A manifest-level change (tempo lives in the manifest) dirties the project
    // and the dirty indicator lights.
    session.setTempo(132);
    await tester.pump();
    expect(controller.isDirty.value, isTrue);
    expect(find.byTooltip('unsaved changes'), findsOneWidget);

    // Open the project menu → Save. The new project has no home, so the picker
    // supplies one; the project is written and the dirty dot clears.
    await tester.tap(menuTrigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(picker.newLocationCallCount, 1);
    expect(controller.isSaved, isTrue);
    expect(store.saveCount, 1);
    expect(controller.isDirty.value, isFalse);
    expect(find.byTooltip('unsaved changes'), findsNothing);
    // The manifest carried the changed tempo.
    final saved = await store.load();
    expect(saved.manifest.tempo, 132);

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
  });

  testWidgets('a dirty journal offers recovery on launch', (tester) async {
    const dir = '/projects/recovered.phi';
    final engine = PhiEngine(
      FakeYseGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    // A previously-saved project whose journal holds one unsaved edit.
    final store = FakeProjectStore();
    final journal = FakeJournalStore();
    final seedSession = SessionState();
    final seedSettings = AppSettingsController(FakeAppSettingsStore());
    final seedController = ProjectController(
      session: seedSession,
      settings: seedSettings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
    );
    await seedController.saveAs(dir); // writes the clean save
    seedController.dispose();
    seedSettings.dispose();
    seedSession.dispose();
    await journal.append(
      jsonEncode(const {'type': 'create_entity', 'address': 'clip.recovered'}),
    );

    // Launch with that project as the most-recent, and auto-restore on.
    final settings = AppSettingsController(
      FakeAppSettingsStore(const AppSettings(recentProjects: [dir])),
    );
    final controller = ProjectController(
      session: session,
      settings: settings,
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
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

    // The recovery dialog is offered on launch (design §7, §9).
    expect(find.text('Recover unsaved work?'), findsOneWidget);
    expect(find.textContaining('1 unsaved edit'), findsOneWidget);

    // Replay it: the project opens with the journaled entity rebuilt.
    await tester.tap(find.text('replay all'));
    await tester.pumpAndSettle();

    // The project name (from the recovered manifest) shows in the menu …
    expect(
      find.descendant(
        of: find.byType(ProjectMenu),
        matching: find.text('recovered'),
      ),
      findsOneWidget,
    );
    // … and the journaled entity was replayed into the live registry.
    expect(controller.registry.kinds, contains('clip'));

    controller.dispose();
    settings.dispose();
    session.dispose();
    await engine.dispose();
  });
}
