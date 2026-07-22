import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/domain/log/log_transcript.dart';
import 'package:phi/shell/diagnostics/log_filter_bar.dart';
import 'package:phi/shell/diagnostics/log_panel.dart';
import 'package:phi/shell/diagnostics/log_panel_controller.dart';

void main() {
  late LogStore store;
  var seq = 0;

  LogEntry make({
    LogSource source = LogSource.app,
    LogLevel level = LogLevel.info,
    required String text,
  }) => LogEntry(
    source: source,
    level: level,
    time: DateTime(2026, 1, 1).add(Duration(milliseconds: seq++)),
    text: text,
  );

  setUp(() {
    store = LogStore();
    seq = 0;
  });

  tearDown(() => store.dispose());

  Future<LogPanelController> pump(
    WidgetTester tester, {
    ClipboardWriter? clipboard,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 460));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LogPanelController(store: store, clipboard: clipboard);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: LogPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  // Finds a chip in the filter bar by its (upper-cased) label, unambiguously
  // scoped away from the identically-worded level/source tags on the rows.
  Finder filterChip(String label) => find.descendant(
    of: find.byType(LogFilterBar),
    matching: find.text(label),
  );

  group('follow / pause / jump', () {
    Future<void> seedMany(WidgetTester tester) async {
      for (var i = 0; i < 80; i++) {
        store.add(make(text: 'entry $i'));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('auto-follows to the newest entry on load', (tester) async {
      await pump(tester);
      await seedMany(tester);

      // Pinned to the bottom: the newest is on screen, the oldest scrolled off,
      // and the jump-to-newest affordance is hidden.
      expect(find.text('entry 79'), findsOneWidget);
      expect(find.text('entry 0'), findsNothing);
      expect(find.byKey(LogPanel.jumpToNewestKey), findsNothing);
    });

    testWidgets('a new entry while following scrolls into view', (
      tester,
    ) async {
      await pump(tester);
      await seedMany(tester);

      store.add(make(level: LogLevel.error, text: 'the newest'));
      await tester.pumpAndSettle();
      expect(find.text('the newest'), findsOneWidget);
    });

    testWidgets('scrolling up pauses follow and shows jump-to-newest', (
      tester,
    ) async {
      await pump(tester);
      await seedMany(tester);
      expect(find.byKey(LogPanel.jumpToNewestKey), findsNothing);

      // Drag the list content downward → reveals earlier entries → leaves the
      // bottom → follow pauses.
      await tester.drag(find.byType(ListView), const Offset(0, 250));
      await tester.pumpAndSettle();

      expect(find.byKey(LogPanel.jumpToNewestKey), findsOneWidget);
    });

    testWidgets('jump-to-newest returns to the bottom and resumes follow', (
      tester,
    ) async {
      await pump(tester);
      await seedMany(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(find.byKey(LogPanel.jumpToNewestKey), findsOneWidget);

      await tester.tap(find.byKey(LogPanel.jumpToNewestKey));
      await tester.pumpAndSettle();

      expect(find.byKey(LogPanel.jumpToNewestKey), findsNothing);
      expect(find.text('entry 79'), findsOneWidget);
    });
  });

  group('filters', () {
    Future<void> seedMixed(WidgetTester tester) async {
      store
        ..add(make(source: LogSource.app, level: LogLevel.info, text: 'alpha'))
        ..add(
          make(source: LogSource.engine, level: LogLevel.warning, text: 'beta'),
        )
        ..add(
          make(source: LogSource.python, level: LogLevel.error, text: 'gamma'),
        )
        ..add(
          make(source: LogSource.app, level: LogLevel.debug, text: 'delta'),
        );
      await tester.pumpAndSettle();
    }

    testWidgets('the level chip narrows to that level and above', (
      tester,
    ) async {
      await pump(tester);
      await seedMixed(tester);
      expect(find.text('alpha'), findsOneWidget);

      await tester.tap(filterChip('ERROR'));
      await tester.pumpAndSettle();

      expect(find.text('gamma'), findsOneWidget); // the only error
      expect(find.text('alpha'), findsNothing);
      expect(find.text('beta'), findsNothing);
      expect(find.text('delta'), findsNothing);
    });

    testWidgets('source chips filter by origin, combinable', (tester) async {
      await pump(tester);
      await seedMixed(tester);

      // Turn off python and app → engine only.
      await tester.tap(filterChip('PYTHON'));
      await tester.pumpAndSettle();
      await tester.tap(filterChip('APP'));
      await tester.pumpAndSettle();

      expect(find.text('beta'), findsOneWidget); // engine/warning
      expect(find.text('gamma'), findsNothing); // python
      expect(find.text('alpha'), findsNothing); // app
      expect(find.text('delta'), findsNothing); // app
    });

    testWidgets('level and source filters combine (AND)', (tester) async {
      await pump(tester);
      await seedMixed(tester);

      // Errors only, and only from python → gamma qualifies, nothing else.
      await tester.tap(filterChip('ERROR'));
      await tester.pumpAndSettle();
      await tester.tap(filterChip('ENGINE'));
      await tester.pumpAndSettle();
      await tester.tap(filterChip('APP'));
      await tester.pumpAndSettle();

      expect(find.text('gamma'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('beta'), findsNothing);
    });

    testWidgets('the search field does a text search', (tester) async {
      await pump(tester);
      await seedMixed(tester);

      await tester.enterText(find.byKey(LogFilterBar.searchFieldKey), 'gam');
      await tester.pumpAndSettle();

      expect(find.text('gamma'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('beta'), findsNothing);
    });

    testWidgets('clear-filters appears while narrowing and resets everything', (
      tester,
    ) async {
      final controller = await pump(tester);
      await seedMixed(tester);
      expect(find.byKey(LogPanel.clearKey), findsNothing);

      await tester.tap(filterChip('ERROR'));
      await tester.pumpAndSettle();
      expect(find.byKey(LogPanel.clearKey), findsOneWidget);

      await tester.tap(find.byKey(LogPanel.clearKey));
      await tester.pumpAndSettle();

      expect(controller.filter.isNarrowing, isFalse);
      expect(find.byKey(LogPanel.clearKey), findsNothing);
      expect(find.text('alpha'), findsOneWidget); // everything back
    });

    testWidgets('shows an empty state when nothing matches', (tester) async {
      await pump(tester);
      await seedMixed(tester);

      await tester.enterText(
        find.byKey(LogFilterBar.searchFieldKey),
        'no-such-text',
      );
      await tester.pumpAndSettle();

      expect(find.text('no entries'), findsOneWidget);
    });
  });

  group('copy', () {
    testWidgets('the copy button writes the visible filtered set', (
      tester,
    ) async {
      final captured = <String>[];
      await pump(tester, clipboard: (text) async => captured.add(text));
      store
        ..add(make(level: LogLevel.info, text: 'keep me'))
        ..add(make(level: LogLevel.error, text: 'and me'))
        ..add(make(level: LogLevel.debug, text: 'drop me'));
      await tester.pumpAndSettle();

      // Narrow so the debug line is filtered out of the copy.
      await tester.tap(filterChip('INFO'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LogPanel.copyKey));
      await tester.pump();

      expect(captured, hasLength(1));
      expect(captured.single, contains('keep me'));
      expect(captured.single, contains('and me'));
      expect(captured.single, isNot(contains('drop me')));
      // Paste-ready: exactly the formatted transcript of what is visible.
      final expected = LogTranscript.of(
        store.entries.where((e) => e.level != LogLevel.debug),
      );
      expect(captured.single, expected);
    });
  });

  group('close', () {
    testWidgets('the close button closes the drawer', (tester) async {
      final controller = await pump(tester);
      store.add(make(text: 'hi'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(LogPanel.closeKey));
      await tester.pump();
      expect(controller.isOpen, isFalse);
    });
  });
}
