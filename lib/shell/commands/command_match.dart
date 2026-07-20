import 'phi_command.dart';

/// A [PhiCommand] that survived a palette query, carrying its ranking [score]
/// (higher is a better match) and the title character indices that matched — so
/// the palette can highlight them. Produced by `CommandSearch`.
class CommandMatch {
  const CommandMatch({
    required this.command,
    required this.score,
    this.matchedTitleIndices = const {},
  });

  final PhiCommand command;
  final double score;

  /// Indices into [PhiCommand.title] that the query matched (empty when the
  /// query is empty, or when the match came only from the category).
  final Set<int> matchedTitleIndices;
}
