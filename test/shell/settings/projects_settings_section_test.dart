import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/app_settings.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/shell/settings/projects_settings_section.dart';

import '../../domain/project/test_doubles/fake_app_settings_store.dart';

void main() {
  late FakeAppSettingsStore store;
  late AppSettingsController settings;

  Future<void> pumpSection(WidgetTester tester, AppSettings seed) async {
    store = FakeAppSettingsStore(seed);
    settings = AppSettingsController(store);
    await settings.load();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectsSettingsSection(settings: settings)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the cadence, pinned entries first, then recents', (
    tester,
  ) async {
    await pumpSection(
      tester,
      const AppSettings(
        recentProjects: ['/x/a.phi', '/y/b.phi'],
        pinnedProjects: ['/z/pinned.phi'],
        autosaveInterval: Duration(seconds: 45),
      ),
    );

    expect(find.text('AUTOSAVE'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('RECENT PROJECTS'), findsOneWidget);
    expect(find.text('pinned.phi'), findsOneWidget);
    expect(find.text('a.phi'), findsOneWidget);
    expect(find.text('b.phi'), findsOneWidget);
  });

  testWidgets('editing the cadence to 0 persists a disabled autosave', (
    tester,
  ) async {
    await pumpSection(
      tester,
      const AppSettings(autosaveInterval: Duration(seconds: 60)),
    );

    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(settings.value.autosaveInterval, Duration.zero);
  });

  testWidgets('editing the cadence to a number persists it', (tester) async {
    await pumpSection(
      tester,
      const AppSettings(autosaveInterval: Duration(seconds: 60)),
    );

    await tester.enterText(find.byType(TextField), '15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(settings.value.autosaveInterval, const Duration(seconds: 15));
  });

  testWidgets('removing a recent drops it from settings', (tester) async {
    await pumpSection(
      tester,
      const AppSettings(recentProjects: ['/x/only.phi']),
    );

    await tester.tap(find.byTooltip('remove'));
    await tester.pumpAndSettle();

    expect(settings.value.recentProjects, isEmpty);
    expect(find.text('no recent projects'), findsOneWidget);
  });

  testWidgets('clear all empties the recents list', (tester) async {
    await pumpSection(
      tester,
      const AppSettings(recentProjects: ['/x/a.phi', '/y/b.phi']),
    );

    await tester.tap(find.text('clear all'));
    await tester.pumpAndSettle();

    expect(settings.value.recentProjects, isEmpty);
  });

  testWidgets('pinning moves a recent into pins, unpinning returns it', (
    tester,
  ) async {
    await pumpSection(tester, const AppSettings(recentProjects: ['/x/a.phi']));

    // Pin it: it leaves recents and joins pins.
    await tester.tap(find.byTooltip('pin'));
    await tester.pumpAndSettle();
    expect(settings.value.pinnedProjects, contains('/x/a.phi'));
    expect(settings.value.recentProjects, isEmpty);

    // The row is now a pinned row — unpin returns it to recents.
    await tester.tap(find.byTooltip('unpin'));
    await tester.pumpAndSettle();
    expect(settings.value.pinnedProjects, isEmpty);
    expect(settings.value.recentProjects, contains('/x/a.phi'));
  });

  testWidgets('clear all leaves pinned entries standing', (tester) async {
    await pumpSection(
      tester,
      const AppSettings(
        recentProjects: ['/x/a.phi'],
        pinnedProjects: ['/z/pinned.phi'],
      ),
    );

    await tester.tap(find.text('clear all'));
    await tester.pumpAndSettle();

    expect(settings.value.recentProjects, isEmpty);
    expect(settings.value.pinnedProjects, ['/z/pinned.phi']);
    expect(find.text('pinned.phi'), findsOneWidget);
  });
}
