import 'package:flutter/foundation.dart';

import 'log_level.dart';
import 'log_source.dart';

/// One line of the unified log: where it came from, how severe it is, when it
/// happened, and what it says (design `docs/design/diagnostics.md` §2).
///
/// Immutable and value-equal so the ring-buffer [LogStore] can hold it and the
/// panel can diff cheaply. [time] is supplied by the caller (stamped off the
/// injected `Clock`), never read from `DateTime.now()` in here — the domain
/// keeps time at its seams. [format] renders the entry as one plain, readable
/// line for the session file.
@immutable
class LogEntry {
  /// Creates an entry from its [source], [level], [time], and [text].
  const LogEntry({
    required this.source,
    required this.level,
    required this.time,
    required this.text,
  });

  /// Which stream produced the entry.
  final LogSource source;

  /// How severe the entry is.
  final LogLevel level;

  /// When the entry was recorded (from the injected clock).
  final DateTime time;

  /// The message body — may span multiple lines (e.g. a Python traceback).
  final String text;

  /// Renders the entry as one plain-text line for the session file:
  /// `[2026-07-22 14:33:55.123] ERROR   engine  message`.
  ///
  /// The columns are padded so a hand-opened log lines up; multi-line [text]
  /// keeps its own newlines after the header.
  String format() {
    final level = this.level.wireName.toUpperCase().padRight(7);
    final source = this.source.wireName.padRight(6);
    return '[${_formatTime(time)}] $level $source $text';
  }

  @override
  bool operator ==(Object other) =>
      other is LogEntry &&
      other.source == source &&
      other.level == level &&
      other.time == time &&
      other.text == text;

  @override
  int get hashCode => Object.hash(source, level, time, text);

  @override
  String toString() =>
      'LogEntry(${source.wireName}, ${level.wireName}, '
      '${_formatTime(time)}, $text)';

  static String _formatTime(DateTime t) {
    final y = t.year.toString().padLeft(4, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d $h:$mi:$s.$ms';
  }
}
