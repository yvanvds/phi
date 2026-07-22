import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/core/clock.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/real_log_file_store.dart';
import 'package:phi/domain/log/session_log.dart';

/// A clock returning a fixed instant.
class FixedClock implements Clock {
  const FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('phi_logs_test_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('RealLogFileStore', () {
    test('sessionLogNames is empty when the folder does not exist', () async {
      final store = RealLogFileStore(
        directory: Directory(p.join(temp.path, 'missing')),
      );
      expect(await store.sessionLogNames(), isEmpty);
    });

    test('appendLine creates the folder and file, and really writes', () async {
      final store = RealLogFileStore(
        directory: Directory(p.join(temp.path, 'logs')),
      );
      await store.appendLine('phi-20260722-100000-000.log', 'first line');
      await store.appendLine('phi-20260722-100000-000.log', 'second line');

      final file = File(
        p.join(temp.path, 'logs', 'phi-20260722-100000-000.log'),
      );
      expect(await file.exists(), isTrue);
      expect(
        await file.readAsString(),
        'first line\nsecond line\n',
        reason: 'append-through, plain readable text, newline-terminated',
      );
    });

    test(
      'sessionLogNames returns phi-*.log newest-first, excluding the marker',
      () async {
        final store = RealLogFileStore(directory: temp);
        await store.appendLine('phi-20260101-000000-000.log', 'a');
        await store.appendLine('phi-20260722-235959-000.log', 'b');
        await store.appendLine('not-a-session.txt', 'ignored');
        await store.writeMarker('clean');

        expect(await store.sessionLogNames(), [
          'phi-20260722-235959-000.log',
          'phi-20260101-000000-000.log',
        ]);
      },
    );

    test('the marker lifecycle round-trips on disk', () async {
      final store = RealLogFileStore(directory: temp);
      expect(await store.markerExists(), isFalse);

      await store.writeMarker('clean shutdown');
      expect(await store.markerExists(), isTrue);
      expect(
        await File(
          p.join(temp.path, RealLogFileStore.markerFileName),
        ).readAsString(),
        'clean shutdown\n',
      );

      await store.deleteMarker();
      expect(await store.markerExists(), isFalse);
      await store.deleteMarker(); // deleting a missing marker is not an error
    });

    test(
      'deleteSessionLog removes the file and tolerates a missing one',
      () async {
        final store = RealLogFileStore(directory: temp);
        await store.appendLine('phi-20260101-000000-000.log', 'x');
        await store.deleteSessionLog('phi-20260101-000000-000.log');
        expect(await store.sessionLogNames(), isEmpty);
        await store.deleteSessionLog('phi-20260101-000000-000.log');
      },
    );

    test(
      'a full SessionLog boot/append/close cycle over the real filesystem',
      () async {
        final store = RealLogFileStore(directory: temp);

        // First run: no crash, writes a readable session file, closes cleanly.
        final first = SessionLog(
          files: store,
          clock: FixedClock(DateTime(2026, 7, 22, 10)),
        );
        expect(await first.boot(), isNull);
        await first.append(
          LogEntry(
            source: LogSource.engine,
            level: LogLevel.error,
            time: DateTime(2026, 7, 22, 10, 30, 15, 500),
            text: 'device lost',
          ),
        );
        await first.close();

        final logText = await File(
          p.join(temp.path, first.currentLogName!),
        ).readAsString();
        expect(logText, contains('# Phi session log'));
        expect(logText, contains('ERROR   engine device lost'));

        // Second run: the clean marker is present, so no crash is reported.
        final second = SessionLog(
          files: store,
          clock: FixedClock(DateTime(2026, 7, 22, 11)),
        );
        expect(await second.boot(), isNull);
        expect(second.currentLogName, isNot(first.currentLogName));

        // Third run: second never closed — a crash pointing at second's log.
        final third = SessionLog(
          files: store,
          clock: FixedClock(DateTime(2026, 7, 22, 12)),
        );
        final report = await third.boot();
        expect(report, isNotNull);
        expect(report!.previousLogName, second.currentLogName);
      },
    );
  });
}
