import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_filter.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/domain/log/log_transcript.dart';
import 'package:phi/shell/diagnostics/log_panel_controller.dart';

void main() {
  late LogStore store;
  var seq = 0;

  LogEntry make({
    LogSource source = LogSource.app,
    LogLevel level = LogLevel.info,
    String? text,
  }) => LogEntry(
    source: source,
    level: level,
    time: DateTime(2026, 1, 1).add(Duration(milliseconds: seq)),
    text: text ?? 'entry ${seq++}',
  );

  void addError(String text) =>
      store.add(make(level: LogLevel.error, text: text));

  setUp(() {
    store = LogStore();
    seq = 0;
  });

  tearDown(() => store.dispose());

  group('initial state', () {
    test('starts closed with the default filter and no badge', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      expect(c.isOpen, isFalse);
      expect(c.unseenErrorCount, 0);
      expect(c.hasUnseenErrors, isFalse);
      expect(c.filter, const LogFilter());
      expect(c.visibleEntries, isEmpty);
    });
  });

  group('error badge', () {
    test('accrues one per error recorded while closed', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);

      store.add(make()); // info — not an error
      addError('boom');
      addError('bang');
      expect(c.unseenErrorCount, 2);
      expect(c.hasUnseenErrors, isTrue);
    });

    test('does not accrue while the drawer is open', () {
      final c = LogPanelController(store: store)..open();
      addTearDown(c.dispose);

      addError('while open');
      expect(c.unseenErrorCount, 0);
    });

    test('opening clears the badge', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      addError('boom');
      expect(c.unseenErrorCount, 1);

      c.open();
      expect(c.unseenErrorCount, 0);
      expect(c.isOpen, isTrue);
    });

    test('errors are only counted since the drawer was last open', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);

      addError('before open'); // badge = 1
      c.open(); // clears + rebases
      addError('while open'); // not counted
      c.close(); // rebases to now
      addError('after close'); // badge = 1 (only this one)
      expect(c.unseenErrorCount, 1);
    });

    test('a ring-buffer rollover never over-counts', () {
      store = LogStore(capacity: 3);
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      // Flood with more errors than the buffer holds; the badge counts at most
      // what actually arrived, never more.
      for (var i = 0; i < 10; i++) {
        addError('e$i');
      }
      expect(c.unseenErrorCount, lessThanOrEqualTo(10));
      expect(c.unseenErrorCount, greaterThan(0));
    });
  });

  group('open / close / toggle', () {
    test('toggle flips the open state', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      expect(c.isOpen, isFalse);
      c.toggle();
      expect(c.isOpen, isTrue);
      c.toggle();
      expect(c.isOpen, isFalse);
    });

    test(
      'openFilteredToErrors opens filtered to errors and clears the badge',
      () {
        final c = LogPanelController(store: store);
        addTearDown(c.dispose);
        addError('boom');
        expect(c.unseenErrorCount, 1);

        c.openFilteredToErrors();
        expect(c.isOpen, isTrue);
        expect(c.unseenErrorCount, 0);
        expect(c.filter.minLevel, LogLevel.error);
        expect(c.filter.sources, LogFilter.allSources);
        expect(c.filter.query, '');
      },
    );
  });

  group('filter mutations drive visibleEntries', () {
    test('setMinLevel narrows to that level and above', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      store.add(make(level: LogLevel.info, text: 'i'));
      store.add(make(level: LogLevel.warning, text: 'w'));
      addError('e');

      c.setMinLevel(LogLevel.warning);
      expect(c.visibleEntries.map((e) => e.text), ['w', 'e']);
    });

    test('toggleSource filters by origin', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      store.add(make(source: LogSource.engine, text: 'eng'));
      store.add(make(source: LogSource.python, text: 'py'));
      store.add(make(source: LogSource.app, text: 'app'));

      c
        ..toggleSource(LogSource.python)
        ..toggleSource(LogSource.app);
      expect(c.visibleEntries.map((e) => e.text), ['eng']);
    });

    test('setQuery does a case-insensitive text search', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      store.add(make(text: 'audio DEVICE lost'));
      store.add(make(text: 'unrelated'));

      c.setQuery('device');
      expect(c.visibleEntries.map((e) => e.text), ['audio DEVICE lost']);
    });

    test('clearFilters restores the default', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      c
        ..setMinLevel(LogLevel.error)
        ..setQuery('x');
      expect(c.filter.isNarrowing, isTrue);

      c.clearFilters();
      expect(c.filter, const LogFilter());
    });
  });

  group('copy', () {
    test('copyVisible writes the filtered set as paste-ready text', () async {
      final captured = <String>[];
      final c = LogPanelController(
        store: store,
        clipboard: (text) async => captured.add(text),
      );
      addTearDown(c.dispose);
      store.add(make(level: LogLevel.info, text: 'keep me'));
      addError('and me');
      store.add(make(level: LogLevel.debug, text: 'drop me'));

      c.setMinLevel(LogLevel.info); // drops the debug line
      await c.copyVisible();

      expect(captured, hasLength(1));
      expect(captured.single, LogTranscript.of(c.visibleEntries));
      expect(captured.single, contains('keep me'));
      expect(captured.single, contains('and me'));
      expect(captured.single, isNot(contains('drop me')));
    });
  });

  group('notifications', () {
    test('notifies on a store change and on filter changes', () {
      final c = LogPanelController(store: store);
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      store.add(make()); // store change → re-notify
      c.setQuery('x'); // filter change → notify
      c.open(); // state change → notify
      expect(notifications, 3);
    });
  });
}
