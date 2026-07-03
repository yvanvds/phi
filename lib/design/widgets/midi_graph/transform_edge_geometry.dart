import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'transform_graph_canvas_constants.dart';

/// Endpoints + control points of one cubic-Bézier edge cable.
///
/// A value object so the painter and the click hit-tester share one geometry
/// source instead of redoing the edge-picking and control-offset maths twice
/// and risking drift — the transform-graph twin of `TransitionCurve`.
@immutable
class EdgeCurve {
  const EdgeCurve({
    required this.a,
    required this.b,
    required this.c1,
    required this.c2,
  });

  /// Start point — sits on the source node's right or left edge, whichever
  /// faces the target.
  final Offset a;

  /// End point — same picking rule, mirrored to the target.
  final Offset b;

  /// Outgoing control point near [a].
  final Offset c1;

  /// Incoming control point near [b].
  final Offset c2;
}

/// Pure-function helpers that build and walk the cubic-Bézier edge cables.
/// Widget-free so painters, hit-testers, and tests share one implementation.
abstract final class TransformEdgeGeometry {
  /// Build the cubic for an edge between [src] and [dst] node rects. Endpoints
  /// clip onto whichever vertical edge of the source faces the target so the
  /// cable doesn't run back through its own node.
  static EdgeCurve curveBetween(Rect src, Rect dst) {
    final (a, b) = _pickEdges(src, dst);
    const cx = TransformGraphCanvasConstants.edgeControlOffset;
    final goingRight = b.dx >= a.dx;
    final c1 = Offset(a.dx + (goingRight ? cx : -cx), a.dy);
    final c2 = Offset(b.dx + (goingRight ? -cx : cx), b.dy);
    return EdgeCurve(a: a, b: b, c1: c1, c2: c2);
  }

  /// Point on the cubic at parameter [t] in `[0, 1]` — standard cubic Bézier
  /// evaluation.
  static Offset pointAt(EdgeCurve curve, double t) {
    final mt = 1 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final x =
        mt2 * mt * curve.a.dx +
        3 * mt2 * t * curve.c1.dx +
        3 * mt * t2 * curve.c2.dx +
        t2 * t * curve.b.dx;
    final y =
        mt2 * mt * curve.a.dy +
        3 * mt2 * t * curve.c1.dy +
        3 * mt * t2 * curve.c2.dy +
        t2 * t * curve.b.dy;
    return Offset(x, y);
  }

  /// Approximate Euclidean distance from [point] to [curve] by sampling the
  /// cubic and taking the minimum.
  static double distanceTo(EdgeCurve curve, Offset point) {
    const samples = TransformGraphCanvasConstants.edgeHitSamples;
    if (samples <= 0) return double.infinity;
    var bestSq = double.infinity;
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final d2 = (pointAt(curve, t) - point).distanceSquared;
      if (d2 < bestSq) bestSq = d2;
    }
    return math.sqrt(bestSq);
  }

  static (Offset, Offset) _pickEdges(Rect src, Rect dst) {
    final srcMid = src.center;
    final dstMid = dst.center;
    final dstToTheRight = dstMid.dx >= srcMid.dx;
    final a = Offset(dstToTheRight ? src.right : src.left, srcMid.dy);
    final b = Offset(dstToTheRight ? dst.left : dst.right, dstMid.dy);
    return (a, b);
  }
}
