import 'log_entry.dart';

/// Renders a run of [LogEntry]s to paste-ready plain text (design
/// `docs/design/diagnostics.md` §4, "copy: selection or the visible filtered
/// set, paste-ready").
///
/// Each entry becomes one [LogEntry.format] line — the same columnar shape the
/// session file uses, so a pasted excerpt reads exactly like the on-disk log.
/// Multi-line entries (a Python traceback) keep their own newlines. Pure and
/// static; the report bundle (#272) can reuse it.
abstract final class LogTranscript {
  /// The [entries] joined into one newline-separated block, order preserved.
  static String of(Iterable<LogEntry> entries) =>
      entries.map((e) => e.format()).join('\n');
}
