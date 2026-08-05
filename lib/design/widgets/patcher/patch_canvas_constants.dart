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

  /// Horizontal spacing between successive ports along a node's edge.
  ///
  /// Inlets run along the **top** edge and outlets along the **bottom**
  /// (design §6, §12.1), spread from a fixed [firstPortOffset] inset at this
  /// fixed pitch — rather than distributed evenly across whatever width the
  /// box happens to have. Fixed wins for two reasons. A port's position then
  /// does not depend on the box's width, so a box that grows or shrinks while
  /// it is being retyped in place does not drag its cables sideways with every
  /// keystroke. And it gives the exact minimum width a port count demands
  /// ([minWidthForPorts]) — which is the whole point of moving the ports onto
  /// the horizontal edges: the count sets a *width* floor a line of text
  /// absorbs, instead of a *height* floor no one-line box could survive.
  static const double portSpacing = 26;

  /// Horizontal offset from either vertical edge of a node to the outermost
  /// port's centre. Applied on both sides, so [minWidthForPorts] leaves the
  /// same margin at the right as at the left.
  static const double firstPortOffset = 16;

  /// Default height of a node box the registry has no tuned size for — one
  /// header plus a line of body, the shape a port-count-driven height used to
  /// produce for a single-port object.
  static const double defaultNodeHeight = 64;

  /// Default width floor for a node box, independent of its ports.
  static const double minNodeWidth = 120;

  /// The narrowest box that seats [count] ports along one horizontal edge:
  /// [firstPortOffset] of margin at each end and [portSpacing] between
  /// neighbours. Zero or one port needs no room beyond the margins.
  static double minWidthForPorts(int count) =>
      2 * firstPortOffset + (count > 1 ? (count - 1) * portSpacing : 0);

  /// Visual diameter of a port dot.
  static const double portDotSize = 8;

  /// Half of [portDotSize], used to offset the dot so its centre sits on
  /// the node's edge.
  static const double portDotRadius = portDotSize / 2;

  /// Pixel radius around a port treated as a hit target when **dropping** a
  /// drag-to-create cable. Deliberately generous — a missed drop costs the
  /// user the whole gesture.
  static const double portHitRadius = 16;

  /// Pixel radius around a port treated as a hit target when **pressing**
  /// to start a cable. Tighter than [portHitRadius] so the zone never reaches
  /// beyond the port dot's own neighbourhood: half of [portSpacing], so two
  /// neighbouring ports' press zones meet without overlapping, and a press
  /// anywhere inside the box keeps dragging the node (issue #352).
  static const double portPressRadius = 8;

  /// Bezier control-point **y**-distance from each cable endpoint: a cable
  /// leaves an outlet heading down out of the box's bottom edge and arrives at
  /// an inlet from above its top edge (design §6, issue #377).
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
