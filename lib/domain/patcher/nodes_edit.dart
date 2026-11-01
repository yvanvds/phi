import 'nodes_edit_kind.dart';

/// One write a `.nodes` field sends its object (issue #476), in the field's
/// own units.
class NodesEdit {
  const NodesEdit._(
    this.kind, {
    this.index = 0,
    required this.x,
    required this.y,
    this.radius = 0,
  });

  /// Put the cursor at ([x], [y]).
  const NodesEdit.cursor(double x, double y)
    : this._(NodesEditKind.cursor, x: x, y: y);

  /// Move node [index]'s centre to ([x], [y]).
  const NodesEdit.move(int index, double x, double y)
    : this._(NodesEditKind.move, index: index, x: x, y: y);

  /// Give node [index], centred at ([x], [y]), a new [radius].
  const NodesEdit.resize(int index, double x, double y, double radius)
    : this._(NodesEditKind.resize, index: index, x: x, y: y, radius: radius);

  final NodesEditKind kind;
  final int index;
  final double x;
  final double y;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is NodesEdit &&
      other.kind == kind &&
      other.index == index &&
      other.x == x &&
      other.y == y &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(kind, index, x, y, radius);

  @override
  String toString() => 'NodesEdit($kind, $index, $x, $y, $radius)';
}
