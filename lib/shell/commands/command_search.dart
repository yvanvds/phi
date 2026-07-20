import 'command_match.dart';
import 'phi_command.dart';

/// Pure ranking for the command palette (design `docs/design/shell-layout.md`
/// §4): a subsequence fuzzy match over each command's title (and, more weakly,
/// category), recently-used first. No Flutter, no state — just a function of
/// (query, commands, recents) — so the matching and ordering rules are
/// unit-testable without a widget tree.
abstract final class CommandSearch {
  /// Ranks [commands] for [query]. Disabled commands are dropped (the palette
  /// never shows them).
  ///
  /// With an empty [query], every enabled command is returned most-recently-used
  /// first — [recentIds] gives the recency order, newest first — then the rest in
  /// registration order. With a non-empty query, only fuzzy matches over `title`
  /// or `category` survive, best score first; ties break toward the more recently
  /// used, then registration order.
  static List<CommandMatch> run(
    String query,
    List<PhiCommand> commands, {
    List<String> recentIds = const [],
  }) {
    final enabled = commands.where((c) => c.isEnabled).toList(growable: false);
    final recentRank = <String, int>{
      for (var i = 0; i < recentIds.length; i++) recentIds[i]: i,
    };
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      final ordered = [...enabled]
        ..sort((a, b) => _recencyThenOrder(a, b, enabled, recentRank));
      return [
        for (final command in ordered) CommandMatch(command: command, score: 0),
      ];
    }

    final matches = <CommandMatch>[];
    for (final command in enabled) {
      final match = _match(trimmed, command);
      if (match != null) matches.add(match);
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return _recencyThenOrder(a.command, b.command, enabled, recentRank);
    });
    return matches;
  }

  /// Orders two commands by recency (a smaller [recentRank] — more recent — wins)
  /// then by registration order, so the sort is stable and deterministic.
  static int _recencyThenOrder(
    PhiCommand a,
    PhiCommand b,
    List<PhiCommand> order,
    Map<String, int> recentRank,
  ) {
    const notRecent = 1 << 30;
    final ra = recentRank[a.id] ?? notRecent;
    final rb = recentRank[b.id] ?? notRecent;
    if (ra != rb) return ra.compareTo(rb);
    return order.indexOf(a).compareTo(order.indexOf(b));
  }

  /// The best fuzzy match of [query] against a command, or `null` when neither
  /// its title nor its category contains the query as a subsequence. A title
  /// match wins and yields highlight indices; a category-only match scores lower
  /// and highlights nothing.
  static CommandMatch? _match(String query, PhiCommand command) {
    final onTitle = _fuzzy(query, command.title);
    if (onTitle != null) {
      return CommandMatch(
        command: command,
        score: onTitle.score,
        matchedTitleIndices: onTitle.indices,
      );
    }
    final onCategory = _fuzzy(query, command.category);
    if (onCategory != null) {
      return CommandMatch(command: command, score: onCategory.score * 0.4);
    }
    return null;
  }

  /// Case-insensitive subsequence match of [query] in [text]. Returns `null` when
  /// [query] is not a subsequence; otherwise a score that rewards contiguous runs
  /// and word-boundary hits, plus the matched indices.
  static _Fuzzy? _fuzzy(String query, String text) {
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    final indices = <int>{};
    var cursor = 0;
    var score = 0.0;
    var previous = -2;
    for (var qi = 0; qi < q.length; qi++) {
      final ch = q[qi];
      var found = -1;
      for (var k = cursor; k < t.length; k++) {
        if (t[k] == ch) {
          found = k;
          break;
        }
      }
      if (found == -1) return null;
      indices.add(found);
      score += 1;
      if (found == previous + 1) score += 5; // contiguous with the last hit
      if (found == 0 || _isBoundary(t[found - 1])) score += 8; // word start
      score -= found * 0.05; // prefer earlier matches
      previous = found;
      cursor = found + 1;
    }
    return _Fuzzy(score, indices);
  }

  static bool _isBoundary(String ch) =>
      ch == ' ' || ch == '.' || ch == '_' || ch == '-' || ch == '/';
}

/// A single haystack's fuzzy result — its [score] and matched indices.
class _Fuzzy {
  const _Fuzzy(this.score, this.indices);

  final double score;
  final Set<int> indices;
}
