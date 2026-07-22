/// The severity of a [LogEntry] (design `docs/design/diagnostics.md` §2, §5).
///
/// Ordered least-to-most severe so the panel's level filter can express "this
/// level and above". Engine `LogLevel`s map onto these in the engine layer; the
/// status-bar badge (issue #270) counts [error] entries.
enum LogLevel {
  /// Fine-grained tracing, normally filtered out.
  debug('debug'),

  /// Ordinary progress — the default level for app events.
  info('info'),

  /// Something recoverable that the performer may want to know about.
  warning('warning'),

  /// A failure — badged in the status bar until the panel is opened.
  error('error');

  /// Binds the case to its stable [wireName].
  const LogLevel(this.wireName);

  /// The short, upper-caseable tag written to the log file and shown in filters.
  final String wireName;

  /// Whether this level is at least as severe as [other] — the predicate the
  /// panel's "level and above" filter is built on.
  bool isAtLeast(LogLevel other) => index >= other.index;
}
