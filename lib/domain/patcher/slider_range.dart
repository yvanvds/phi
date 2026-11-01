import 'patch_args.dart';

/// The span one axis of a multi-value slider covers — the `minimum maximum`
/// creation parameters of `.rslider` and `.multislider`, and each axis pair of
/// `.xyslider` (issue #472).
///
/// The engine takes the two bounds as an **ordered pair**, so bounds given the
/// wrong way round still bound against the right two numbers; [low] and [high]
/// are therefore always sorted. Everything a body draws is a 0–1 [positionOf]
/// inside this span, and everything it sends is a [valueAt] back out of it, in
/// the object's own units — these objects report and take real values, not
/// positions.
class SliderRange {
  /// A span from [a] to [b], in either order.
  SliderRange(double a, double b) : low = a < b ? a : b, high = a < b ? b : a;

  /// Read the two bounds at positional argument [at] and the one after it from
  /// [args]. A missing or unparseable bound keeps the engine default, 0 and
  /// 127 — Max's default size of 128, counted from 0.
  factory SliderRange.fromArgs(String args, {int at = 0}) {
    final parts = splitPatchArgs(args);
    double read(int i, double fallback) =>
        i < parts.length ? double.tryParse(parts[i]) ?? fallback : fallback;
    return SliderRange(read(at, 0), read(at + 1, 127));
  }

  /// The lower bound.
  final double low;

  /// The upper bound.
  final double high;

  /// Where [value] sits in the span, 0 at [low] to 1 at [high], clamped. A
  /// zero-width span puts every value at 0.
  double positionOf(double value) {
    final span = high - low;
    if (span <= 0 || !value.isFinite) return 0;
    return ((value - low) / span).clamp(0.0, 1.0);
  }

  /// The value at [position] (clamped to 0–1 first).
  double valueAt(double position) =>
      low + (high - low) * position.clamp(0.0, 1.0);

  /// [value] spelled for a message to the engine: at most six decimals, no
  /// trailing zeros, and `0` rather than `-0`.
  static String format(double value) {
    final fixed = value.toStringAsFixed(6);
    final trimmed = fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
    return trimmed == '-0' ? '0' : trimmed;
  }
}
