import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/shell/diagnostics/log_panel_controller.dart';
import 'package:phi/shell/diagnostics/log_panel_toggle.dart';

void main() {
  late LogStore store;
  var seq = 0;

  LogEntry error(String text) => LogEntry(
    source: LogSource.app,
    level: LogLevel.error,
    time: DateTime(2026, 1, 1).add(Duration(milliseconds: seq++)),
    text: text,
  );

  setUp(() {
    store = LogStore();
    seq = 0;
  });

  tearDown(() => store.dispose());

  Future<LogPanelController> pump(WidgetTester tester) async {
    final controller = LogPanelController(store: store);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: LogPanelToggle(controller: controller),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('shows a LOG label and no badge when there are no errors', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('LOG'), findsOneWidget);
    expect(find.byKey(LogPanelToggle.badgeKey), findsNothing);
  });

  testWidgets('badges the count of unseen errors', (tester) async {
    await pump(tester);

    store
      ..add(error('boom'))
      ..add(error('bang'));
    await tester.pump();

    expect(find.byKey(LogPanelToggle.badgeKey), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping with a badge opens filtered to errors and clears it', (
    tester,
  ) async {
    final controller = await pump(tester);
    store.add(error('boom'));
    await tester.pump();
    expect(find.byKey(LogPanelToggle.badgeKey), findsOneWidget);

    await tester.tap(find.byKey(LogPanelToggle.toggleKey));
    await tester.pump();

    expect(controller.isOpen, isTrue);
    expect(controller.filter.minLevel, LogLevel.error);
    expect(controller.unseenErrorCount, 0);
    expect(find.byKey(LogPanelToggle.badgeKey), findsNothing);
  });

  testWidgets('tapping without a badge just toggles open/closed', (
    tester,
  ) async {
    final controller = await pump(tester);

    await tester.tap(find.byKey(LogPanelToggle.toggleKey));
    await tester.pump();
    expect(controller.isOpen, isTrue);
    // The default (unnarrowed) filter — a plain toggle does not force errors.
    expect(controller.filter.isNarrowing, isFalse);

    await tester.tap(find.byKey(LogPanelToggle.toggleKey));
    await tester.pump();
    expect(controller.isOpen, isFalse);
  });
}
