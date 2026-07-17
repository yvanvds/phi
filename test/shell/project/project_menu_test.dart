import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/shell/project/project_menu.dart';

import '../../domain/project/test_doubles/fake_app_settings_store.dart';
import '../../domain/project/test_doubles/fake_journal_store.dart';
import '../../domain/project/test_doubles/fake_project_directory_picker.dart';
import '../../domain/project/test_doubles/fake_project_store.dart';

void main() {
  late SessionState session;
  late FakeProjectStore store;
  late FakeJournalStore journal;
  late ProjectController controller;

  ProjectController build() {
    session = SessionState();
    store = FakeProjectStore();
    journal = FakeJournalStore();
    return ProjectController(
      session: session,
      settingsStore: FakeAppSettingsStore(),
      storeFactory: (_) => store,
      journalStoreFactory: (_) => journal,
    );
  }

  tearDown(() {
    controller.dispose();
    session.dispose();
  });

  Future<void> pumpMenu(
    WidgetTester tester,
    FakeProjectDirectoryPicker picker,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ProjectMenu(controller: controller, picker: picker),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opening the menu lists every lifecycle action', (tester) async {
    controller = build();
    await pumpMenu(tester, FakeProjectDirectoryPicker());

    await tester.tap(find.text('untitled')); // the menu trigger
    await tester.pumpAndSettle();

    expect(find.text('New'), findsOneWidget);
    expect(find.text('Open…'), findsOneWidget);
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Duplicate…'), findsOneWidget);
    expect(find.text('Rename…'), findsOneWidget);
  });

  testWidgets('Save on a new project prompts for a location and binds it', (
    tester,
  ) async {
    controller = build();
    final picker = FakeProjectDirectoryPicker(
      newLocationPath: '/projects/untitled.phi',
    );
    await pumpMenu(tester, picker);

    expect(controller.isSaved, isFalse);

    await tester.tap(find.text('untitled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The location picker was reached with the project name as the suggestion,
    // and the project is now bound + written.
    expect(picker.newLocationCallCount, 1);
    expect(picker.lastSuggestedName, 'untitled');
    expect(controller.isSaved, isTrue);
    expect(controller.location.value, '/projects/untitled.phi');
    expect(store.saveCount, 1);
  });

  testWidgets('Open Recent lists the recent projects', (tester) async {
    controller = build();
    // A save records the project as a recent and names it after the folder.
    await controller.saveAs('/projects/my_set.phi');
    expect(controller.name.value, 'my_set');
    await pumpMenu(tester, FakeProjectDirectoryPicker());

    await tester.tap(find.text('my_set')); // trigger shows the derived name
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();

    // The recent's folder basename appears in the submenu.
    expect(find.text('my_set.phi'), findsWidgets);
  });

  testWidgets('Rename applies a new name from the dialog', (tester) async {
    controller = build();
    await pumpMenu(tester, FakeProjectDirectoryPicker());

    await tester.tap(find.text('untitled'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nightset');
    await tester.tap(find.text('rename'));
    await tester.pumpAndSettle();

    expect(controller.name.value, 'nightset');
    expect(controller.isDirty.value, isTrue);
  });
}
