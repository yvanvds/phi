import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_transcript.dart';

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

  group('LogTranscript.of', () {
    test('is empty for no entries', () {
      expect(LogTranscript.of(const []), '');
    });

    test('renders one entry as its formatted line', () {
      final line = LogTranscript.of([entry(text: 'device lost')]);
      expect(line, entry(text: 'device lost').format());
      // The columnar session-file shape, so a paste reads like the log file.
      expect(line, contains('[2026-07-22 14:33:55.123]'));
      expect(line, contains('INFO'));
      expect(line, contains('app'));
      expect(line, contains('device lost'));
    });

    test('joins many entries with newlines, order preserved', () {
      final text = LogTranscript.of([
        entry(text: 'first'),
        entry(source: LogSource.engine, level: LogLevel.error, text: 'second'),
        entry(text: 'third'),
      ]);
      final lines = text.split('\n');
      expect(lines, hasLength(3));
      expect(lines[0], contains('first'));
      expect(lines[1], contains('second'));
      expect(lines[2], contains('third'));
    });

    test('keeps a multi-line entry\'s own newlines', () {
      final text = LogTranscript.of([
        entry(
          source: LogSource.python,
          level: LogLevel.error,
          text: 'Traceback:\n  line 2',
        ),
      ]);
      expect(text, contains('Traceback:\n  line 2'));
    });
  });
}
