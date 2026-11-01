import 'patch_args.dart';

/// A `.preset` object's creation argument, `[slots]` (issue #477).
///
/// Read the way the engine reads its one parameter (`gPreset::ShapeStore`):
/// tokens that are not numbers are skipped, and the first number is the bank's
/// capacity, truncated and clamped to 1–1024, default 32. Changing it replaces
/// the object, so a new capacity always starts with empty slots.
class PresetArgs {
  const PresetArgs({required this.slots});

  /// Parse [args]. A missing capacity keeps the engine default.
  factory PresetArgs.parse(String args) {
    final numbers = [for (final t in splitPatchArgs(args)) ?double.tryParse(t)];
    if (numbers.isEmpty) return const PresetArgs(slots: defaultSlots);
    final n = numbers.first;
    // `ExprToInt`: truncate, and a value it cannot hold becomes 0.
    final whole = n.isFinite && n.abs() < 2147483648 ? n.truncate() : 0;
    return PresetArgs(slots: whole.clamp(minSlots, maxSlots));
  }

  /// Slots with no argument (`gPreset::DEFAULT_SLOTS`).
  static const int defaultSlots = 32;

  /// The fewest slots a bank holds (`MIN_SLOTS`).
  static const int minSlots = 1;

  /// The most slots a bank holds (`MAX_SLOTS`).
  static const int maxSlots = 1024;

  /// How many slots the bank holds, numbered 0 to `slots - 1`.
  final int slots;
}
