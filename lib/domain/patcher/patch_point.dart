/// A node's `(x, y)` position on the patcher canvas — a pure-Dart point so the
/// patcher domain stays free of `dart:ui`/Flutter (the layer rule in
/// `CLAUDE.md`).
///
/// Positions ride in the engine object's GUI properties, so they round-trip in
/// the dump alongside the graph (design `docs/design/patcher.md` §3); this value
/// type is only the coordinate a move gesture carries and a delete captures for
/// its undo.
class PatchPoint {
  /// Builds a point at ([x], [y]) in canvas-local logical pixels.
  const PatchPoint(this.x, this.y);

  /// Reads a point from a decoded `{x, y}` map; missing coordinates default to
  /// `0`.
  factory PatchPoint.fromJson(Map<String, Object?> json) => PatchPoint(
    (json['x'] as num?)?.toDouble() ?? 0,
    (json['y'] as num?)?.toDouble() ?? 0,
  );

  /// Horizontal position.
  final double x;

  /// Vertical position.
  final double y;

  /// The point as a `{x, y}` JSON map.
  Map<String, Object?> toJson() => {'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchPoint && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PatchPoint($x, $y)';
}
