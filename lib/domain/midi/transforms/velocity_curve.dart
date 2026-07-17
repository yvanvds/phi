import 'velocity_curve_shape.dart';

/// A serialisable, declarative mapping from a normalised velocity `[0, 1]`
/// onto a parameter value — the data model behind [VelocityToParameterTransform]
/// (issue #108).
///
/// It replaces the bare `double Function(double)` callback the transform used
/// to hold: a plain function can't be inspected, edited, or round-tripped, so
/// there was nothing a curve editor could mutate. This model is pure,
/// immutable, and value-equal, so it edits in place through `copyWith`, survives
/// a param seam, and keeps the chain memoisable.
///
/// The mapping is a [shape] applied to the input, then scaled onto the
/// `[valueAt0, valueAt1]` output range. Both ends are exact regardless of shape,
/// and the range may invert (`valueAt0 > valueAt1`) to map louder playing onto a
/// *lower* parameter value. The [VelocityCurve.identity] default maps velocity
/// straight through onto `[0, 1]`, so a fresh chip is a no-op the performer
/// makes meaningful by editing alone.
class VelocityCurve {
  const VelocityCurve({
    this.shape = VelocityCurveShape.linear,
    this.valueAt0 = 0,
    this.valueAt1 = 1,
    this.steps = 4,
  });

  /// Identity mapping: velocity passes straight through onto `[0, 1]`. The
  /// passthrough default a catalogue-added `vel → param` chip starts from.
  const VelocityCurve.identity() : this();

  /// How the input bends between the two ends before scaling. See
  /// [VelocityCurveShape].
  final VelocityCurveShape shape;

  /// Output value at velocity `0` (the low end of the input range).
  final double valueAt0;

  /// Output value at velocity `1` (the high end of the input range).
  final double valueAt1;

  /// Number of discrete levels for [VelocityCurveShape.stepped]; ignored by the
  /// other shapes. Clamped to at least `1` on evaluation.
  final int steps;

  /// Maps a [velocity] (clamped to `[0, 1]`) onto its parameter value.
  double valueAt(double velocity) {
    final v = velocity.clamp(0.0, 1.0);
    final t = _shaped(v);
    return valueAt0 + t * (valueAt1 - valueAt0);
  }

  /// The normalised position `[0, 1]` the shape maps [v] (already clamped) to.
  double _shaped(double v) {
    switch (shape) {
      case VelocityCurveShape.linear:
        return v;
      case VelocityCurveShape.exponential:
        return v * v;
      case VelocityCurveShape.logarithmic:
        final inv = 1 - v;
        return 1 - inv * inv;
      case VelocityCurveShape.stepped:
        final levels = steps < 1 ? 1 : steps;
        if (levels == 1) return 0;
        return (v * (levels - 1)).round() / (levels - 1);
    }
  }

  VelocityCurve copyWith({
    VelocityCurveShape? shape,
    double? valueAt0,
    double? valueAt1,
    int? steps,
  }) => VelocityCurve(
    shape: shape ?? this.shape,
    valueAt0: valueAt0 ?? this.valueAt0,
    valueAt1: valueAt1 ?? this.valueAt1,
    steps: steps ?? this.steps,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VelocityCurve &&
          other.shape == shape &&
          other.valueAt0 == valueAt0 &&
          other.valueAt1 == valueAt1 &&
          other.steps == steps;

  @override
  int get hashCode => Object.hash(shape, valueAt0, valueAt1, steps);

  @override
  String toString() =>
      'VelocityCurve(${shape.label}, $valueAt0 → $valueAt1, steps: $steps)';
}
