import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';

void main() {
  group('LogEntry', () {
    LogEntry entry({
      LogSource source = LogSource.engine,
      LogLevel level = LogLevel.info,
      DateTime? time,
      String text = 'hello',
    }) => LogEntry(
      source: source,
      level: level,
      time: time ?? DateTime(2026, 7, 22, 14, 33, 55, 123),
      text: text,
    );

    test('value equality over all four fields', () {
      expect(entry(), entry());
      expect(entry().hashCode, entry().hashCode);
      expect(entry(level: LogLevel.error), isNot(entry()));
      expect(entry(source: LogSource.app), isNot(entry()));
      expect(entry(text: 'other'), isNot(entry()));
      expect(entry(time: DateTime(2026)), isNot(entry()));
    });

    test('format renders a padded, readable single line', () {
      expect(
        entry(
          source: LogSource.engine,
          level: LogLevel.error,
          text: 'boom',
        ).format(),
        '[2026-07-22 14:33:55.123] ERROR   engine boom',
      );
    });

    test('format zero-pads every time component', () {
      final line = entry(
        time: DateTime(2026, 1, 2, 3, 4, 5, 6),
        text: 'x',
      ).format();
      expect(line, startsWith('[2026-01-02 03:04:05.006]'));
    });

    test('format keeps multi-line text (a traceback) after the header', () {
      final line = entry(
        level: LogLevel.error,
        source: LogSource.python,
        text: 'Traceback:\n  File "<script>", line 1',
      ).format();
      expect(line, contains('\n  File "<script>", line 1'));
      expect(line, startsWith('[2026-07-22 14:33:55.123] ERROR   python '));
    });
  });
}
