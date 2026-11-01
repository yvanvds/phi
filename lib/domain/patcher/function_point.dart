import 'dart:math' as math;

/// One breakpoint of a `.function` (issue #475): an [x], a [y], and the
/// [curve] that shapes the segment *arriving* at it from the point before.
///
/// The GUI value spells a point as one cell, `<x> <y> <curve>`, and the cells
/// come in ascending-x order.
class FunctionPoint {
  const FunctionPoint(this.x, this.y, [this.curve = 0]);

  /// Read one GUI value cell, `<x> <y> <curve>`. Null for a cell that does not
  /// hold at least an x and a y (an empty cell, or a stale one).
  static FunctionPoint? parse(String cell) {
    final parts = cell.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    if (x == null || y == null) return null;
    final curve = parts.length > 2 ? double.tryParse(parts[2]) ?? 0 : 0.0;
    return FunctionPoint(x, y, curve);
  }

  /// Where along the domain the point sits.
  final double x;

  /// The point's value.
  final double y;

  /// The arriving segment's curvature in [-1, 1]; 0 is a straight line.
  final double curve;

  /// The segment shape `gFunction::Shape` draws: position [t] in [0, 1]
  /// through curve [c], `t^((1+c)/(1-c))`. A positive curve leaves its start
  /// late, a negative one early, and the ±1 limits are steps — held to the
  /// end at +1, jumped at the start at −1.
  static double shape(double t, double c) {
    if (c == 0) return t;
    if (c >= 1) return t >= 1 ? 1 : 0;
    if (c <= -1) return t > 0 ? 1 : 0;
    return math.pow(t, (1 + c) / (1 - c)).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is FunctionPoint &&
      other.x == x &&
      other.y == y &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(x, y, curve);

  @override
  String toString() => 'FunctionPoint($x, $y, $curve)';
}
