/// Shared metrics for the MIDI transform-graph canvas. Held in one place so
/// the edge layer, the node frame, and the canvas itself agree on node
/// geometry and grid alignment — the transform-graph counterpart of
/// `StateCanvasConstants`.
abstract final class TransformGraphCanvasConstants {
  /// Total canvas size in logical pixels. Big enough to feel infinite for now;
  /// can be replaced with a smarter viewport later.
  static const double canvasSize = 4000;

  /// Snap step for node drags — matches the 16px backdrop grid.
  static const double snapStep = 16;

  /// Transform-node width in logical pixels. Wide enough for the kind tag, a
  /// mockup label like `transpose · +3 st`, and the active pill.
  static const double nodeWidth = 156;

  /// Transform-node height in logical pixels.
  static const double nodeHeight = 46;

  /// The clip-source node is narrower — it carries only the `SOURCE` caption
  /// and the clip's note count.
  static const double sourceNodeWidth = 104;

  /// Visual diameter of a node's output port.
  static const double portSize = 10;

  /// Pixel radius around the output port treated as the hit target that starts
  /// a drag-to-connect gesture.
  static const double portHitRadius = 18;

  /// Pixel padding around a node treated as the hit target when *dropping* a
  /// drag-to-connect cable. Lets the performer aim at the whole node.
  static const double nodeHitPadding = 8;

  /// Stroke width of an edge cable.
  static const double edgeStroke = 1.4;

  /// Arrowhead length (tip → base along the cable direction).
  static const double arrowHeadLength = 9;

  /// Arrowhead half-width perpendicular to the cable direction.
  static const double arrowHeadHalfWidth = 4;

  /// Distance the cubic Bézier control points sit out from each endpoint along
  /// the source/target horizontal axis.
  static const double edgeControlOffset = 70;

  /// Click-distance threshold for hit-testing an edge cable, in canvas-local
  /// pixels.
  static const double edgeHitThreshold = 12;

  /// Number of sample points along the cubic Bézier the edge hit-test walks.
  static const int edgeHitSamples = 24;

  /// Font size of the condition label painted on a cable.
  static const double edgeLabelFontSize = 9;
}
