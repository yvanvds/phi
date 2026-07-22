import 'package:flutter/foundation.dart';

import 'log_entry.dart';
import 'log_level.dart';
import 'log_source.dart';

/// The log panel's combinable query (design `docs/design/diagnostics.md` §4):
/// a minimum severity, a set of included [LogSource]s, and a free-text search —
/// all applied together (AND).
///
/// Pure and immutable so the panel controller can hold it, diff it, and the
/// filtering logic is unit-tested with no Flutter and no widgets. [apply] runs
/// the three predicates over the store's entries in one pass, preserving order.
@immutable
class LogFilter {
  /// Creates a filter. The defaults are the "show everything" state: every
  /// source, the lowest level ([LogLevel.debug], so nothing is hidden), and no
  /// search text.
  const LogFilter({
    this.minLevel = LogLevel.debug,
    this.sources = allSources,
    this.query = '',
  });

  /// Every log source — the default (nothing filtered out by source).
  static const Set<LogSource> allSources = {
    LogSource.engine,
    LogSource.python,
    LogSource.app,
  };

  /// The least-severe level shown: an entry passes when it [LogLevel.isAtLeast]
  /// this. So [LogLevel.warning] shows warnings and errors, hiding info/debug.
  final LogLevel minLevel;

  /// The sources shown — an entry passes when its source is in here. Empty means
  /// nothing matches (every source filtered out).
  final Set<LogSource> sources;

  /// A case-insensitive substring the entry text must contain. Empty matches
  /// every entry (no text filtering).
  final String query;

  /// Whether this filter is the "show everything" default — used to enable a
  /// "clear filters" affordance only when a filter is actually narrowing.
  bool get isNarrowing =>
      minLevel != LogLevel.debug ||
      sources.length != allSources.length ||
      query.isNotEmpty;

  /// Whether [entry] passes all three predicates.
  bool matches(LogEntry entry) {
    if (!entry.level.isAtLeast(minLevel)) return false;
    if (!sources.contains(entry.source)) return false;
    if (query.isEmpty) return true;
    return entry.text.toLowerCase().contains(query.toLowerCase());
  }

  /// The subset of [entries] that pass, order preserved.
  List<LogEntry> apply(Iterable<LogEntry> entries) =>
      entries.where(matches).toList(growable: false);

  /// A copy with [minLevel] replaced.
  LogFilter withMinLevel(LogLevel level) =>
      LogFilter(minLevel: level, sources: sources, query: query);

  /// A copy with [source] toggled in or out of [sources].
  LogFilter withToggledSource(LogSource source) {
    final next = Set<LogSource>.of(sources);
    if (!next.remove(source)) next.add(source);
    return LogFilter(minLevel: minLevel, sources: next, query: query);
  }

  /// A copy with the search [text] replaced.
  LogFilter withQuery(String text) =>
      LogFilter(minLevel: minLevel, sources: sources, query: text);

  @override
  bool operator ==(Object other) =>
      other is LogFilter &&
      other.minLevel == minLevel &&
      setEquals(other.sources, sources) &&
      other.query == query;

  @override
  int get hashCode =>
      Object.hash(minLevel, query, Object.hashAllUnordered(sources));

  @override
  String toString() =>
      'LogFilter(minLevel: ${minLevel.wireName}, '
      'sources: ${sources.map((s) => s.wireName).join('+')}, query: "$query")';
}
