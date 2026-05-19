/// Shared metrics for the patcher canvas. Held in one place so the cable
/// layer, the port dot, and the node frame agree on where ports live.
abstract final class PatchCanvasConstants {
  /// Total canvas size in logical pixels. Big enough to feel infinite
  /// for the first PR; will be replaced with an actually-unbounded
  /// surface (or a smarter viewport) later.
  static const double canvasSize = 4000;

  /// Backdrop grid cell size — minor dots.
  static const double gridCell = 16;

  /// Backdrop grid major-line size.
  static const double gridMajor = 64;

  /// Header height of a node — uppercase mono title area.
  static const double headerHeight = 22;

  /// Vertical spacing between successive ports inside the node body.
  static const double portSpacing = 26;

  /// Vertical offset from the top of the body to the first port's centre.
  static const double firstPortOffset = 16;

  /// Visual diameter of a port dot.
  static const double portDotSize = 8;

  /// Half of [portDotSize], used to offset the dot so its centre sits on
  /// the node's edge.
  static const double portDotRadius = portDotSize / 2;

  /// Pixel radius around a port treated as a hit target when dropping a
  /// drag-to-create cable.
  static const double portHitRadius = 16;

  /// Bezier control-point x-distance from each cable endpoint. Matches
  /// the design preview's `cx1 = a.x + 60` constant.
  static const double cableControlOffset = 60;
}
