import 'package:flutter_test/flutter_test.dart';
import 'package:phi/core/clock.dart';
import 'package:phi/domain/log/log_file_store.dart';
import 'package:phi/domain/log/log_level.dart';
import 'package:phi/domain/log/log_recorder.dart';
import 'package:phi/domain/log/log_source.dart';
import 'package:phi/domain/log/log_store.dart';
import 'package:phi/domain/log/session_log.dart';

/// A minimal in-memory [LogFileStore], enough to prove the recorder's file
/// mirror lands (and skips) the right lines.
class _FakeLogFileStore implements LogFileStore {
  final Map<String, StringBuffer> files = {};
  String? marker;

  @override
  Future<List<String>> sessionLogNames() async =>
      files.keys.toList()..sort((a, b) => b.compareTo(a));

  @override
  Future<void> appendLine(String name, String line) async =>
      (files[name] ??= StringBuffer()).writeln(line);

  @override
  Future<void> deleteSessionLog(String name) async => files.remove(name);

  @override
  Future<bool> markerExists() async => marker != null;

  @override
  Future<void> writeMarker(String note) async => marker = note;

  @override
  Future<void> deleteMarker() async => marker = null;
}

class _FixedClock implements Clock {
  _FixedClock(this.instant);
  DateTime instant;
  @override
  DateTime now() => instant;
}

void main() {
  group('LogRecorder', () {
    test('stamps entries off the injected clock', () {
      final store = LogStore();
      final clock = _FixedClock(DateTime(2026, 7, 22, 14, 33, 55));
      LogRecorder(store: store, clock: clock).app('booted');

      expect(store.length, 1);
      expect(store.entries.single.time, DateTime(2026, 7, 22, 14, 33, 55));
    });

    test('engine() tags source engine at the given level (info default)', () {
      final store = LogStore();
      final recorder = LogRecorder(store: store);
      recorder.engine('device opened');
      recorder.engine('callback overran', level: LogLevel.error);

      expect(store.entries[0].source, LogSource.engine);
      expect(store.entries[0].level, LogLevel.info);
      expect(store.entries[1].source, LogSource.engine);
      expect(store.entries[1].level, LogLevel.error);
    });

    test('python() tags source python at error level', () {
      final store = LogStore();
      LogRecorder(
        store: store,
      ).python('Traceback (most recent call last): ...');

      expect(store.entries.single.source, LogSource.python);
      expect(store.entries.single.level, LogLevel.error);
    });

    test('app() tags source app at the given level (info default)', () {
      final store = LogStore();
      final recorder = LogRecorder(store: store);
      recorder.app('project saved');
      recorder.app('device unavailable', level: LogLevel.warning);

      expect(store.entries[0].source, LogSource.app);
      expect(store.entries[0].level, LogLevel.info);
      expect(store.entries[1].level, LogLevel.warning);
    });

    test('mirrors to the session file once it is booted', () async {
      final store = LogStore();
      final fs = _FakeLogFileStore();
      final sessionLog = SessionLog(
        files: fs,
        clock: _FixedClock(DateTime(2026, 7, 22, 10)),
      );
      await sessionLog.boot();
      final recorder = LogRecorder(store: store, sessionLog: sessionLog);

      recorder.app('written to disk');
      await Future<void>.delayed(Duration.zero); // let the fire-and-forget land

      final contents = fs.files[sessionLog.currentLogName]!.toString();
      expect(contents, contains('written to disk'));
    });

    test('does not touch the file before the session is booted', () async {
      final store = LogStore();
      final fs = _FakeLogFileStore();
      // Not booted: currentLogName is null, so the mirror is skipped.
      final sessionLog = SessionLog(files: fs);
      final recorder = LogRecorder(store: store, sessionLog: sessionLog);

      recorder.app('pre-boot');
      await Future<void>.delayed(Duration.zero);

      expect(store.length, 1, reason: 'still lands in the ring buffer');
      expect(fs.files, isEmpty, reason: 'but nothing is written to disk');
    });
  });
}
