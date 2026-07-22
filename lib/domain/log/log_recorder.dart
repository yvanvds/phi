import 'dart:async';

import '../../core/clock.dart';
import 'log_entry.dart';
import 'log_level.dart';
import 'log_source.dart';
import 'log_store.dart';
import 'session_log.dart';

/// The single write path into the unified log (design `docs/design/diagnostics.md`
/// §2): every source — the engine stream, Python tracebacks, and the app's own
/// notices — records through here rather than touching [LogStore] directly.
///
/// It stamps each entry off the injected [clock] (keeping `DateTime.now()` out of
/// the callers), appends it to the in-memory ring buffer [store], and — when a
/// [sessionLog] has been booted — mirrors it to the session file (design §2: "the
/// stream replaces the engine's own file sink by design — our session file is the
/// sink now"). Pure Dart, so the whole path is unit-tested against a fake store /
/// session log with no Flutter and no disk.
class LogRecorder {
  /// Records into [store], optionally mirroring to a booted [sessionLog], with
  /// timestamps from [clock] (defaulting to the real wall clock).
  LogRecorder({
    required this.store,
    this.sessionLog,
    this.clock = const SystemClock(),
  });

  /// The in-memory ring buffer every entry lands in.
  final LogStore store;

  /// The session file mirror, or `null` when no file sink is wired (tests, or a
  /// bare shell). Entries are appended only once it has been booted.
  final SessionLog? sessionLog;

  /// Where entry timestamps come from.
  final Clock clock;

  /// Records one entry: stamps it, appends to the [store], and — when the
  /// [sessionLog] is booted — mirrors it to the session file.
  void record({
    required LogSource source,
    required LogLevel level,
    required String text,
  }) {
    final entry = LogEntry(
      source: source,
      level: level,
      time: clock.now(),
      text: text,
    );
    store.add(entry);

    // Fire-and-forget file mirror: a slow disk never stalls a live set, and an
    // entry recorded before [SessionLog.boot] (currentLogName still `null`) stays
    // in the ring buffer only. A failed write is swallowed — logging the failure
    // of a log write would only recurse. Crash surfacing of the file is #272.
    final sl = sessionLog;
    if (sl != null && sl.currentLogName != null) {
      unawaited(sl.append(entry).catchError((Object _) {}));
    }
  }

  /// Records an engine-sourced entry (design §2). Level is supplied by the caller
  /// because yse's `Log.messages` stream carries no structured level.
  void engine(String text, {LogLevel level = LogLevel.info}) =>
      record(source: LogSource.engine, level: level, text: text);

  /// Records a Python-sourced entry at [LogLevel.error] — the interpreter's
  /// uncaught tracebacks (design §2).
  void python(String text) =>
      record(source: LogSource.python, level: LogLevel.error, text: text);

  /// Records an app-sourced entry (design §2, §3) — the notice channel's log half.
  void app(String text, {LogLevel level = LogLevel.info}) =>
      record(source: LogSource.app, level: level, text: text);
}
