import 'dart:math' as math;

import 'field_node.dart';

/// The `.nodes` algorithm (issue #476), as `gNodes::CALC` computes it, so a
/// body can shade each node by the weight the object sends without asking the
/// engine for it (no read reports the weights).
///
/// For a cursor at (cx, cy), node *i* at (x, y) with radius r:
///
///     d(i) = sqrt((cx - x)² + (cy - y)²)     the distance (outlet 1)
///     p(i) = max(0, 1 - d(i) / r)            the proximity, 0 outside
///     w(i) = p(i) / Σp                       the weight (outlet 0)
///
/// The weights sum to 1 wherever the cursor is inside any node, and are all 0
/// where it is inside none. A radius of 0 or less (or a NaN) covers nothing.
abstract final class NodesField {
  /// The distance from (cx, cy) to each node, in node order.
  static List<double> distances(List<FieldNode> nodes, double cx, double cy) =>
      [for (final n in nodes) _distance(n, cx, cy)];

  /// Each node's weight for a cursor at (cx, cy), in node order.
  static List<double> weights(List<FieldNode> nodes, double cx, double cy) {
    final proximity = [
      for (final n in nodes) _proximity(_distance(n, cx, cy), n.radius),
    ];
    final total = proximity.fold(0.0, (sum, p) => sum + p);
    return [for (final p in proximity) total > 0 ? p / total : 0.0];
  }

  static double _distance(FieldNode n, double cx, double cy) {
    final dx = cx - n.x;
    final dy = cy - n.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// `gNodes::Proximity`: written as the negation of what must hold, so a NaN
  /// takes the zero branch.
  static double _proximity(double distance, double radius) {
    if (!(radius > 0)) return 0;
    if (!(distance < radius)) return 0;
    return 1 - distance / radius;
  }
}
