/// Shared metrics for the state-machine canvas. Held in one place so the
/// transition layer, the node frame, and the canvas itself agree on node
/// geometry and grid alignment.
abstract final class StateCanvasConstants {
  /// Total canvas size in logical pixels. Big enough to feel infinite for
  /// the first PR; can be replaced with a smarter viewport later.
  static const double canvasSize = 4000;

  /// Snap step for state-node drags — matches the 16px backdrop grid.
  static const double snapStep = 16;

  /// Node width in logical pixels (matches the design system preview's
  /// rounded-square state nodes).
  static const double nodeWidth = 120;

  /// Node height in logical pixels.
  static const double nodeHeight = 56;

  /// Visual diameter of a corner pin.
  static const double pinSize = 6;

  /// Pixel radius around a corner pin treated as the hit target when
  /// dropping a drag-to-create transition.
  static const double pinHitRadius = 14;

  /// Pixel radius around a node treated as the hit target when dropping
  /// a drag-to-create transition. Lets the performer aim at the whole
  /// node, not just a pin.
  static const double nodeHitPadding = 6;

  /// Stroke width of a transition arrow.
  static const double transitionStroke = 1.4;

  /// Arrowhead length (tip → base along the arrow direction).
  static const double arrowHeadLength = 9;

  /// Arrowhead half-width perpendicular to the arrow direction.
  static const double arrowHeadHalfWidth = 4;

  /// Distance the cubic Bézier control points sit out from each endpoint
  /// along the source/target horizontal axis. Matches the design
  /// preview's `cx1 = a.x + 80` feel.
  static const double transitionControlOffset = 80;
}
