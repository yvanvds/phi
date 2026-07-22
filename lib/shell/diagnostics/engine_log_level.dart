import '../../domain/log/log_level.dart';

/// Classifies a raw engine log line into a [LogLevel] (design
/// `docs/design/diagnostics.md` §2).
///
/// yse's `Log.messages` stream carries plain strings with no structured level,
/// so the level is inferred from the text: a line mentioning an error or failure
/// is an [LogLevel.error] (so it badges in the status bar, §5), a warning is a
/// [LogLevel.warning], and everything else is ordinary [LogLevel.info] progress.
/// A heuristic, deliberately conservative — the exact wording of an engine line
/// is not a contract, so this only ever changes which *bucket* a line lands in,
/// never whether it is logged.
LogLevel engineLogLevel(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('error') ||
      lower.contains('fatal') ||
      lower.contains('fail')) {
    return LogLevel.error;
  }
  if (lower.contains('warning') || lower.contains('warn')) {
    return LogLevel.warning;
  }
  return LogLevel.info;
}
