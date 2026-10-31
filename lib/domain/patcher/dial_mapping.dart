import 'dart:math' as math;

import 'patch_args.dart';

/// How a `.dial` maps its 0–1 knob position onto the value it sends — its
/// four positional creation arguments, `minimum maximum exponent intMode`
/// (issue #470).
///
/// The engine keeps the *position* as the dial's GUI value, because that is
/// what it takes back on inlet 0; the mapped value only ever leaves on the
/// outlet, and no read reports it. A readout that shows what the knob sends
/// therefore has to apply the mapping itself. This is libYSE's `MapRange`
/// (`gRangeMap.h`) with the dial's arguments — input 0–1, clipped to the
/// output range, rounded half away from zero in int mode — restated in pure
/// Dart so the surface never touches the engine for it.
class DialMapping {
  const DialMapping({
    this.minimum = 0,
    this.maximum = 1,
    this.exponent = 1,
    this.intMode = false,
  });

  /// Read a dial's creation arguments. A missing or unparseable argument keeps
  /// its engine default (0, 1, 1, float), the same as an omitted one does on
  /// the native side.
  factory DialMapping.fromArgs(String args) {
    final parts = splitPatchArgs(args);
    double at(int i, double fallback) =>
        i < parts.length ? double.tryParse(parts[i]) ?? fallback : fallback;
    return DialMapping(
      minimum: at(0, 0),
      maximum: at(1, 1),
      exponent: at(2, 1),
      intMode: at(3, 0) != 0,
    );
  }

  /// The value sent at position 0.
  final double minimum;

  /// The value sent at position 1.
  final double maximum;

  /// The curve of the mapping; 1 is a straight line.
  final double exponent;

  /// Whether the dial rounds to, and sends, an int.
  final bool intMode;

  /// The value the dial sends at [position] (clamped to 0–1 first, as the
  /// object clamps what it stores).
  double map(double position) {
    final p = position.clamp(0.0, 1.0);
    final curved = exponent == 1
        ? p
        : math.pow(p, exponent).toDouble(); // p >= 0, so no sign branch.
    var result = minimum + (maximum - minimum) * curved;
    if (!result.isFinite) result = 0;
    final lo = math.min(minimum, maximum);
    final hi = math.max(minimum, maximum);
    result = result.clamp(lo, hi).toDouble();
    // `round` in Dart rounds half away from zero, as std::round does.
    return intMode ? result.roundToDouble() : result;
  }

  /// The readout for [position]: an int in int mode, otherwise the mapped
  /// value to at most three decimals, without trailing zeros.
  String format(double position) {
    final v = map(position);
    if (intMode) return '${v.toInt()}';
    final fixed = v.toStringAsFixed(3);
    final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
    return trimmed == '-0' ? '0' : trimmed;
  }
}
