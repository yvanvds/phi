import 'dart:math' as math;
import 'dart:ui';

import 'patch_canvas_constants.dart';

/// Pure-function helpers for the patcher's cable cubic — shared by the hit-test
/// so clicking a cable and painting it agree on one curve. The cubic matches
/// [PatchCablePainter]'s: **vertical** control points a fixed
/// [PatchCanvasConstants.cableControlOffset] out from each endpoint, so the
/// wire leaves the outlet downward and reaches the inlet from above (#377).
abstract final class PatchCableGeometry {
  /// Point on the cable's cubic at parameter [t] in `[0, 1]`, between output
  /// [a] and input [b].
  static Offset pointAt(Offset a, Offset b, double t) {
    const cy = PatchCanvasConstants.cableControlOffset;
    final c1 = Offset(a.dx, a.dy + cy);
    final c2 = Offset(b.dx, b.dy - cy);
    final mt = 1 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final x =
        mt2 * mt * a.dx +
        3 * mt2 * t * c1.dx +
        3 * mt * t2 * c2.dx +
        t2 * t * b.dx;
    final y =
        mt2 * mt * a.dy +
        3 * mt2 * t * c1.dy +
        3 * mt * t2 * c2.dy +
        t2 * t * b.dy;
    return Offset(x, y);
  }

  /// Approximate Euclidean distance from [point] to the cable between [a] and
  /// [b], by sampling the cubic and taking the minimum.
  static double distanceTo(Offset a, Offset b, Offset point) {
    const samples = PatchCanvasConstants.cableHitSamples;
    var bestSq = double.infinity;
    for (var i = 0; i <= samples; i++) {
      final d2 = (pointAt(a, b, i / samples) - point).distanceSquared;
      if (d2 < bestSq) bestSq = d2;
    }
    return math.sqrt(bestSq);
  }
}
