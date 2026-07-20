import '../../domain/shell_layout/shell_layout.dart';

/// Recomputes a split's [fractions] when the splitter handle between child
/// [leadingIndex] and its successor is dragged by [deltaFraction] of the split's
/// main-axis extent (design `docs/design/shell-layout.md` §2 — "splitter drag
/// resizes sibling fractions with sensible minima").
///
/// Only the two panes flanking the handle change; the delta is added to the
/// leading pane and taken from the trailing one, so the pair's combined size —
/// and therefore the whole list's sum — is preserved (no reflow of distant
/// siblings). Both flanks are clamped to at least [minFraction] (default
/// [ShellLayout.minFraction]), so a hard drag pins the shrinking pane at the
/// minimum instead of collapsing it. A pair already too small to hold two minima,
/// an out-of-range [leadingIndex], or a zero delta returns the list unchanged.
///
/// Pure and Flutter-free: the widget converts pixels to a fraction and hands the
/// result to [ShellLayout.resize] (which re-clamps and renormalises defensively),
/// so this stays a unit-testable computation.
List<double> resizeSiblings({
  required List<double> fractions,
  required int leadingIndex,
  required double deltaFraction,
  double minFraction = ShellLayout.minFraction,
}) {
  if (leadingIndex < 0 || leadingIndex + 1 >= fractions.length) {
    return fractions;
  }
  final leading = fractions[leadingIndex];
  final trailing = fractions[leadingIndex + 1];
  final pair = leading + trailing;
  final lo = minFraction;
  final hi = pair - minFraction;
  // The pair cannot host two minima — leave it be rather than force an overlap.
  if (hi < lo) return fractions;
  final newLeading = (leading + deltaFraction).clamp(lo, hi);
  if (newLeading == leading) return fractions;
  final result = [...fractions];
  result[leadingIndex] = newLeading;
  result[leadingIndex + 1] = pair - newLeading;
  return result;
}
