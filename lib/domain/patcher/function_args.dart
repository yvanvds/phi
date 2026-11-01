import 'patch_args.dart';
import 'slider_range.dart';

/// A `.function`'s creation arguments, `points [minimum] [maximum]`
/// (issue #475).
///
/// Read the way `gFunction::ShapeStore` reads them: tokens that are not
/// numbers are skipped, the first number is the point capacity (truncated,
/// clamped to 2–1024, default 128) and the next two the y range (default 0
/// and 1). The engine bounds every y against the sorted pair, so [range] is
/// always low to high.
class FunctionArgs {
  const FunctionArgs({required this.capacity, required this.range});

  /// Parse [args]. Anything missing keeps its engine default.
  factory FunctionArgs.parse(String args) {
    final numbers = [for (final t in splitPatchArgs(args)) ?double.tryParse(t)];
    var capacity = defaultCapacity;
    if (numbers.isNotEmpty) {
      final n = numbers[0];
      // `ExprToInt`: truncate, and a value it cannot hold becomes 0.
      final whole = n.isFinite && n.abs() < 2147483648 ? n.truncate() : 0;
      capacity = whole.clamp(minCapacity, maxCapacity);
    }
    double bound(int i, double fallback) =>
        i < numbers.length ? numbers[i] : fallback;
    return FunctionArgs(
      capacity: capacity,
      range: SliderRange(bound(1, 0), bound(2, 1)),
    );
  }

  /// The engine's capacity with no argument (`gFunction::DEFAULT_POINTS`).
  static const int defaultCapacity = 128;

  /// The fewest points a store can be built for (`MIN_POINTS`).
  static const int minCapacity = 2;

  /// The most points a store can be built for (`MAX_POINTS`).
  static const int maxCapacity = 1024;

  /// How many points the function can hold; a point past it is refused.
  final int capacity;

  /// The span every y is clamped into.
  final SliderRange range;
}
