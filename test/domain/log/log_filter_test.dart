import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_filter.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';

void main() {
  LogEntry entry({
    LogSource source = LogSource.app,
    LogLevel level = LogLevel.info,
    String text = 'hello',
  }) => LogEntry(
    source: source,
    level: level,
    time: DateTime(2026, 7, 22, 14, 33, 55, 123),
    text: text,
  );

  group('LogFilter defaults', () {
    test('the default shows everything', () {
      const filter = LogFilter();
      expect(filter.minLevel, LogLevel.debug);
      expect(filter.sources, LogFilter.allSources);
      expect(filter.query, '');
      expect(filter.isNarrowing, isFalse);
      for (final source in LogSource.values) {
        for (final level in LogLevel.values) {
          expect(filter.matches(entry(source: source, level: level)), isTrue);
        }
      }
    });
  });

  group('level predicate (this level and above)', () {
    test('minLevel warning hides info and debug, keeps warning and error', () {
      const filter = LogFilter(minLevel: LogLevel.warning);
      expect(filter.matches(entry(level: LogLevel.debug)), isFalse);
      expect(filter.matches(entry(level: LogLevel.info)), isFalse);
      expect(filter.matches(entry(level: LogLevel.warning)), isTrue);
      expect(filter.matches(entry(level: LogLevel.error)), isTrue);
      expect(filter.isNarrowing, isTrue);
    });

    test('minLevel error keeps only errors', () {
      const filter = LogFilter(minLevel: LogLevel.error);
      expect(filter.matches(entry(level: LogLevel.warning)), isFalse);
      expect(filter.matches(entry(level: LogLevel.error)), isTrue);
    });
  });

  group('source predicate', () {
    test('only entries in the source set pass', () {
      const filter = LogFilter(sources: {LogSource.engine});
      expect(filter.matches(entry(source: LogSource.engine)), isTrue);
      expect(filter.matches(entry(source: LogSource.python)), isFalse);
      expect(filter.matches(entry(source: LogSource.app)), isFalse);
      expect(filter.isNarrowing, isTrue);
    });

    test('an empty source set matches nothing', () {
      const filter = LogFilter(sources: {});
      for (final source in LogSource.values) {
        expect(filter.matches(entry(source: source)), isFalse);
      }
    });

    test('toggling a source removes it, toggling again restores it', () {
      const base = LogFilter();
      final without = base.withToggledSource(LogSource.python);
      expect(without.sources, isNot(contains(LogSource.python)));
      expect(without.sources, contains(LogSource.engine));

      final restored = without.withToggledSource(LogSource.python);
      expect(restored.sources, contains(LogSource.python));
      expect(restored.sources, LogFilter.allSources);
    });
  });

  group('text search', () {
    test('is a case-insensitive substring match', () {
      final filter = const LogFilter().withQuery('DEVICE');
      expect(filter.matches(entry(text: 'audio device lost')), isTrue);
      expect(filter.matches(entry(text: 'nothing here')), isFalse);
      expect(filter.isNarrowing, isTrue);
    });

    test('an empty query matches every entry', () {
      final filter = const LogFilter().withQuery('');
      expect(filter.matches(entry(text: 'anything')), isTrue);
    });
  });

  group('combinable predicates', () {
    test('all three narrow together (AND)', () {
      const filter = LogFilter(
        minLevel: LogLevel.warning,
        sources: {LogSource.engine},
      );
      final tight = filter.withQuery('xrun');
      // Passes only when level AND source AND text all match.
      expect(
        tight.matches(
          entry(
            source: LogSource.engine,
            level: LogLevel.error,
            text: 'xrun 3',
          ),
        ),
        isTrue,
      );
      // Right source + text, wrong level.
      expect(
        tight.matches(
          entry(source: LogSource.engine, level: LogLevel.info, text: 'xrun 3'),
        ),
        isFalse,
      );
      // Right level + text, wrong source.
      expect(
        tight.matches(
          entry(source: LogSource.app, level: LogLevel.error, text: 'xrun 3'),
        ),
        isFalse,
      );
    });

    test('apply returns the passing subset in order', () {
      final entries = [
        entry(level: LogLevel.info, text: 'a'),
        entry(level: LogLevel.error, text: 'b'),
        entry(level: LogLevel.warning, text: 'c'),
        entry(level: LogLevel.error, text: 'd'),
      ];
      const filter = LogFilter(minLevel: LogLevel.error);
      expect(filter.apply(entries).map((e) => e.text), ['b', 'd']);
    });
  });

  group('value equality', () {
    test('same fields are equal regardless of source-set instance', () {
      const a = LogFilter(minLevel: LogLevel.warning, sources: {LogSource.app});
      // A distinct instance carrying the same fields (a fresh Set built at
      // runtime, so no const canonicalisation collapses them into one object).
      final b = LogFilter(
        minLevel: LogLevel.warning,
        sources: {LogSource.app}.toSet(),
      );
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields are unequal', () {
      const a = LogFilter();
      expect(a, isNot(const LogFilter(minLevel: LogLevel.error)));
      expect(a, isNot(const LogFilter(sources: {LogSource.app})));
      expect(a, isNot(a.withQuery('x')));
    });
  });
}
