import 'package:flutter_test/flutter_test.dart';
import 'package:phi/core/clock.dart';
import 'package:phi/domain/log/log_entry.dart';
import 'package:phi/domain/log/log_file_store.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/session_log.dart';

/// An in-memory [LogFileStore] mirroring the real one's contract: session names
/// come back newest-first, the marker is a single nullable slot.
class FakeLogFileStore implements LogFileStore {
  final Map<String, StringBuffer> files = {};
  String? marker;

  @override
  Future<List<String>> sessionLogNames() async {
    final names = files.keys.toList()..sort((a, b) => b.compareTo(a));
    return names;
  }

  @override
  Future<void> appendLine(String name, String line) async {
    (files[name] ??= StringBuffer()).writeln(line);
  }

  @override
  Future<void> deleteSessionLog(String name) async {
    files.remove(name);
  }

  @override
  Future<bool> markerExists() async => marker != null;

  @override
  Future<void> writeMarker(String note) async {
    marker = note;
  }

  @override
  Future<void> deleteMarker() async {
    marker = null;
  }
}

/// A clock whose instant is set explicitly, so file-name stamps are predictable.
class ManualClock implements Clock {
  ManualClock(this.at);
  DateTime at;
  @override
  DateTime now() => at;
}

void main() {
  late FakeLogFileStore fs;

  setUp(() => fs = FakeLogFileStore());

  LogEntry appEntry(String text) => LogEntry(
    source: LogSource.app,
    level: LogLevel.info,
    time: DateTime(2026, 7, 22, 9),
    text: text,
  );

  group('SessionLog boot — crash detection', () {
    test('first-ever boot is not a crash and opens a session file', () async {
      final log = SessionLog(
        files: fs,
        clock: ManualClock(DateTime(2026, 7, 22, 10)),
      );

      final report = await log.boot();

      expect(report, isNull);
      expect(log.currentLogName, 'phi-20260722-100000-000.log');
      expect(fs.files.keys, contains(log.currentLogName));
      expect(
        fs.files[log.currentLogName].toString(),
        contains('# Phi session log'),
      );
    });

    test(
      'a present clean-shutdown marker means a clean exit; it is consumed',
      () async {
        fs.marker = 'clean shutdown earlier';
        fs.files['phi-20260722-090000-000.log'] = StringBuffer('prior\n');
        final log = SessionLog(
          files: fs,
          clock: ManualClock(DateTime(2026, 7, 22, 10)),
        );

        final report = await log.boot();

        expect(
          report,
          isNull,
          reason: 'marker present => previous exit was clean',
        );
        expect(fs.marker, isNull, reason: 'the marker is consumed at boot');
      },
    );

    test(
      'a missing marker with a prior log means the previous session crashed',
      () async {
        fs.files['phi-20260722-080000-000.log'] = StringBuffer('older\n');
        fs.files['phi-20260722-093000-000.log'] = StringBuffer('newest\n');
        final log = SessionLog(
          files: fs,
          clock: ManualClock(DateTime(2026, 7, 22, 10)),
        );

        final report = await log.boot();

        expect(report, isNotNull);
        expect(
          report!.previousLogName,
          'phi-20260722-093000-000.log',
          reason: 'the crash points at the newest pre-existing log',
        );
      },
    );
  });

  group('SessionLog marker lifecycle', () {
    test(
      'close writes the marker; the next boot reads it as a clean exit',
      () async {
        final clock = ManualClock(DateTime(2026, 7, 22, 10));
        final first = SessionLog(files: fs, clock: clock);
        await first.boot();
        await first.close();
        expect(fs.marker, isNotNull);

        clock.at = DateTime(2026, 7, 22, 11);
        final second = SessionLog(files: fs, clock: clock);
        final report = await second.boot();

        expect(report, isNull);
        expect(fs.marker, isNull);
      },
    );

    test(
      'a boot with no close (crash) is detected by the following boot',
      () async {
        final clock = ManualClock(DateTime(2026, 7, 22, 10));
        final crashed = SessionLog(files: fs, clock: clock);
        await crashed.boot(); // no close() — the session "crashes"
        final crashedName = crashed.currentLogName;

        clock.at = DateTime(2026, 7, 22, 11);
        final next = SessionLog(files: fs, clock: clock);
        final report = await next.boot();

        expect(report?.previousLogName, crashedName);
      },
    );
  });

  group('SessionLog append', () {
    test('append writes the formatted entry to the current file', () async {
      final log = SessionLog(
        files: fs,
        clock: ManualClock(DateTime(2026, 7, 22, 10)),
      );
      await log.boot();

      final entry = appEntry('project opened');
      await log.append(entry);

      final contents = fs.files[log.currentLogName].toString();
      expect(contents, contains(entry.format()));
    });

    test('append before boot throws', () async {
      final log = SessionLog(
        files: fs,
        clock: ManualClock(DateTime(2026, 7, 22, 10)),
      );
      expect(() => log.append(appEntry('x')), throwsStateError);
    });
  });

  group('SessionLog retention', () {
    test(
      'prunes to the newest [retention] sessions, this one included',
      () async {
        // Seed 25 prior sessions with sortable stamps.
        for (var i = 0; i < 25; i++) {
          final stamp = '2026060${(i ~/ 10)}-${(i % 10)}00000-000';
          fs.files['phi-$stamp.log'] = StringBuffer('old $i\n');
        }
        final log = SessionLog(
          files: fs,
          clock: ManualClock(DateTime(2026, 12, 31, 23, 59, 59)),
          retention: 20,
        );

        await log.boot();

        expect(fs.files.length, 20, reason: 'newest 20 kept, older pruned');
        expect(fs.files.keys, contains(log.currentLogName));
      },
    );

    test('the pruned files are the oldest ones', () async {
      final clock = ManualClock(DateTime(2026, 1, 1));
      // Three prior sessions; retention 2 keeps the newest one + the fresh boot.
      fs.files['phi-20260101-000000-000.log'] = StringBuffer(); // oldest
      fs.files['phi-20260102-000000-000.log'] = StringBuffer();
      fs.files['phi-20260103-000000-000.log'] = StringBuffer(); // newest prior
      clock.at = DateTime(2026, 6, 1);
      final log = SessionLog(files: fs, clock: clock, retention: 2);

      await log.boot();

      expect(fs.files.keys, contains(log.currentLogName));
      expect(fs.files.keys, contains('phi-20260103-000000-000.log'));
      expect(fs.files.keys, isNot(contains('phi-20260101-000000-000.log')));
      expect(fs.files.keys, isNot(contains('phi-20260102-000000-000.log')));
    });

    test('does not prune when under the retention limit', () async {
      fs.files['phi-20260101-000000-000.log'] = StringBuffer();
      final log = SessionLog(
        files: fs,
        clock: ManualClock(DateTime(2026, 6, 1)),
        retention: 20,
      );

      await log.boot();

      expect(fs.files.length, 2); // the prior one + the fresh boot
    });
  });
}
