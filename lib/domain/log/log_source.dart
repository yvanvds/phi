/// Where a [LogEntry] came from (design `docs/design/diagnostics.md` §2).
///
/// The unified log merges three streams, each entry tagged with its origin so
/// the panel (issue #270) can filter by source. Each case carries a stable
/// [wireName] used both in the panel's filter chips and in the plain-text
/// session file, chosen to read naturally in a hand-opened log.
enum LogSource {
  /// The audio engine — yse `Log.messages`, levels mapped from its `LogLevel`.
  engine('engine'),

  /// The embedded Python interpreter — `LiveCoding.errors` tracebacks.
  python('python'),

  /// Phi itself — project open/save/recovery, device changes, degradation
  /// notices surfaced through the notice channel.
  app('app');

  /// Binds the case to its stable [wireName].
  const LogSource(this.wireName);

  /// The short, human-readable tag written to the log file and shown in filters.
  final String wireName;
}
