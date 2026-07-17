/// The response shape a [VelocityCurve] applies to a normalised velocity
/// before it is scaled onto the output range.
///
/// Each shape is a pure mapping of the normalised input `[0, 1]` onto a
/// normalised position `[0, 1]`, keeping both endpoints exact (`0 → 0`,
/// `1 → 1`) so switching shape never moves the range's ends, only how the
/// middle bends. The [label] is what the curve editor's shape picker shows.
enum VelocityCurveShape {
  /// Straight line — the middle of the range tracks the middle of the input.
  linear('linear'),

  /// Ease-in (`v²`): soft playing stays low, accents pull away hard near the
  /// top. Emphasises loud notes.
  exponential('exponential'),

  /// Ease-out (`1 − (1 − v)²`): soft playing already lifts most of the way,
  /// accents add little. Emphasises quiet notes.
  logarithmic('logarithmic'),

  /// Quantised staircase — the input snaps to one of a fixed number of evenly
  /// spaced levels (see [VelocityCurve.steps]).
  stepped('stepped');

  const VelocityCurveShape(this.label);

  /// Display label for the curve editor's shape picker.
  final String label;
}
