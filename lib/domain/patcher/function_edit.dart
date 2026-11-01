import 'function_edit_kind.dart';

/// One write a breakpoint editor sends a `.function` (issue #475), in the
/// object's own units. [index] is the point's position in ascending-x order.
class FunctionEdit {
  const FunctionEdit._(this.kind, {this.index = 0, this.x = 0, this.y = 0})
    : curve = 0;

  const FunctionEdit._curve(this.index, this.curve)
    : kind = FunctionEditKind.curve,
      x = 0,
      y = 0;

  /// Add a point at ([x], [y]).
  const FunctionEdit.add(double x, double y)
    : this._(FunctionEditKind.add, x: x, y: y);

  /// Move point [index] to ([x], [y]).
  const FunctionEdit.move(int index, double x, double y)
    : this._(FunctionEditKind.move, index: index, x: x, y: y);

  /// Re-curve the segment arriving at point [index].
  const FunctionEdit.curve(int index, double curve) : this._curve(index, curve);

  /// Remove point [index].
  const FunctionEdit.remove(int index)
    : this._(FunctionEditKind.remove, index: index);

  final FunctionEditKind kind;
  final int index;
  final double x;
  final double y;
  final double curve;

  @override
  bool operator ==(Object other) =>
      other is FunctionEdit &&
      other.kind == kind &&
      other.index == index &&
      other.x == x &&
      other.y == y &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(kind, index, x, y, curve);

  @override
  String toString() => 'FunctionEdit($kind, $index, $x, $y, $curve)';
}
