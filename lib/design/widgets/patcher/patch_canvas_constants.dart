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

  /// Pixel radius around a port treated as a hit target when **dropping** a
  /// drag-to-create cable. Deliberately generous — a missed drop costs the
  /// user the whole gesture.
  static const double portHitRadius = 16;

  /// Pixel radius around an outlet treated as a hit target when **pressing**
  /// to start a cable. Tighter than [portHitRadius] so the zone never reaches
  /// beyond the port dot's own neighbourhood: the first port centre sits
  /// [firstPortOffset] below the header, so a header press can never be
  /// mistaken for a cable start, and a body press keeps dragging the node
  /// (issue #352).
  static const double portPressRadius = 8;

  /// Bezier control-point x-distance from each cable endpoint. Matches
  /// the design preview's `cx1 = a.x + 60` constant.
  static const double cableControlOffset = 60;

  /// Click-distance threshold for hit-testing a cable, in canvas-local pixels.
  static const double cableHitThreshold = 8;

  /// How near one of a cable's endpoints a press must land to **grab** that end
  /// and re-route it (issue #359). Larger than [portPressRadius] — which claims
  /// the dot itself for starting a *new* cable — so the two gestures share the
  /// same neighbourhood without competing: on the dot starts a cable, just off
  /// it along the wire detaches the one already there.
  static const double cableGrabRadius = 28;

  /// Number of sample points along a cable's cubic the hit-test walks.
  static const int cableHitSamples = 24;
}
