/// One circular node of a `.nodes` field (issue #476): a centre ([x], [y]) and
/// the [radius] it reaches, all in the field's own units.
///
/// The GUI value spells a node as one cell, `<x> <y> <radius>`, one cell per
/// node in node order.
class FieldNode {
  const FieldNode(this.x, this.y, this.radius);

  /// Read one GUI value cell, `<x> <y> <radius>`. Null for a cell that does not
  /// hold three numbers (an empty cell, or a stale one).
  static FieldNode? parse(String cell) {
    final parts = cell.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return null;
    final x = double.tryParse(parts[0]);
    final y = double.tryParse(parts[1]);
    final radius = double.tryParse(parts[2]);
    if (x == null || y == null || radius == null) return null;
    return FieldNode(x, y, radius);
  }

  final double x;
  final double y;

  /// How far the node reaches. 0 or less covers nothing — a muted node.
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is FieldNode &&
      other.x == x &&
      other.y == y &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(x, y, radius);

  @override
  String toString() => 'FieldNode($x, $y, $radius)';
}
