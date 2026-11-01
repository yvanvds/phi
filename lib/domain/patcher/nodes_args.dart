import 'patch_args.dart';

/// A `.nodes` object's creation argument, `[count]` (issue #476).
///
/// Read the way the engine reads its one parameter: tokens that are not
/// numbers are skipped, and the first number is the node count, truncated and
/// clamped to 1–64 (`gNodes::MIN_NODES` / `MAX_NODES`), default 4.
///
/// The count is only where the field **starts**: a whole-field list of another
/// length changes it afterwards, so a body sizes itself from the live cell
/// count, never from this.
class NodesArgs {
  const NodesArgs({required this.count});

  /// Parse [args]. A missing count keeps the engine default.
  factory NodesArgs.parse(String args) {
    final numbers = [for (final t in splitPatchArgs(args)) ?double.tryParse(t)];
    if (numbers.isEmpty) return const NodesArgs(count: defaultCount);
    final n = numbers.first;
    // `ExprToInt`: truncate, and a value it cannot hold becomes 0.
    final whole = n.isFinite && n.abs() < 2147483648 ? n.truncate() : 0;
    return NodesArgs(count: whole.clamp(minCount, maxCount));
  }

  /// Nodes with no argument (`gNodes::DEFAULT_NODES`).
  static const int defaultCount = 4;

  /// The fewest nodes a field holds (`MIN_NODES`).
  static const int minCount = 1;

  /// The most nodes a field holds (`MAX_NODES`).
  static const int maxCount = 64;

  /// The radius every node starts with (`DEFAULT_RADIUS`), at the origin.
  static const double defaultRadius = 1;

  /// How many nodes the object is created with.
  final int count;
}
