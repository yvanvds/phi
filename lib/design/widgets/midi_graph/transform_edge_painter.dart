import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/midi/graph/transform_edge.dart';
import '../../../domain/midi/graph/transform_node_id.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import 'transform_edge_geometry.dart';
import 'transform_graph_canvas_constants.dart';

/// Painter for the guarded cables between transform-graph nodes.
///
/// Each [TransformEdge] is a cubic Bézier between the source and target node
/// rects, with an arrowhead at the target and the edge's
/// `EdgeCondition.label` painted mid-cable (e.g. `state · s3`, `always`).
/// Edges in [activeEdges] — those open under the current context *and*
/// reachable from the source — render solid and bright; the rest render
/// dashed and dim, so the canvas mirrors the active subgraph. Skips any edge
/// whose endpoints are missing.
///
/// Imports the domain edge/id types the same way `StateTransitionPainter`
/// imports its transition types — a painter is the one design-layer place that
/// reads the model it draws.
class TransformEdgePainter extends CustomPainter {
  TransformEdgePainter({
    required this.edges,
    required this.nodeRects,
    required this.activeEdges,
    required this.version,
  });

  final List<TransformEdge> edges;
  final Map<TransformNodeId, Rect> nodeRects;

  /// Edges currently carrying notes — drawn solid + bright. Everything else is
  /// drawn dashed + dim.
  final Set<TransformEdge> activeEdges;

  /// Graph mutation counter. Folded into [shouldRepaint] alongside the node
  /// rects and active set, since a node *move* or an active-state flip changes
  /// the drawing without bumping the graph's version.
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final src = nodeRects[e.fromId];
      final dst = nodeRects[e.toId];
      if (src == null || dst == null) continue;
      final active = activeEdges.contains(e);
      _drawEdge(canvas, src, dst, e.condition.label, active: active);
    }
  }

  void _drawEdge(
    Canvas canvas,
    Rect src,
    Rect dst,
    String label, {
    required bool active,
  }) {
    final color = active ? PhiColors.fg1 : PhiColors.fg3;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = TransformGraphCanvasConstants.edgeStroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final curve = TransformEdgeGeometry.curveBetween(src, dst);
    final path = Path()
      ..moveTo(curve.a.dx, curve.a.dy)
      ..cubicTo(
        curve.c1.dx,
        curve.c1.dy,
        curve.c2.dx,
        curve.c2.dy,
        curve.b.dx,
        curve.b.dy,
      );
    canvas.drawPath(active ? path : _dashed(path, dash: 5, gap: 4), stroke);
    _drawArrowHead(canvas, curve.b, curve.c2, fill);
    _drawLabel(canvas, TransformEdgeGeometry.pointAt(curve, 0.5), label, color);
  }

  void _drawLabel(Canvas canvas, Offset center, String label, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: PhiType.monoS().copyWith(
          fontSize: TransformGraphCanvasConstants.edgeLabelFontSize,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = PhiColors.bg2,
    );
    tp.paint(canvas, rect.topLeft + const Offset(4, 2));
  }

  static void _drawArrowHead(
    Canvas canvas,
    Offset tip,
    Offset from,
    Paint fill,
  ) {
    final dx = tip.dx - from.dx;
    final dy = tip.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final ux = dx / len;
    final uy = dy / len;
    final px = -uy;
    final py = ux;
    const head = TransformGraphCanvasConstants.arrowHeadLength;
    const half = TransformGraphCanvasConstants.arrowHeadHalfWidth;
    final base = Offset(tip.dx - ux * head, tip.dy - uy * head);
    final left = Offset(base.dx + px * half, base.dy + py * half);
    final right = Offset(base.dx - px * half, base.dy - py * half);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, fill);
  }

  static Path _dashed(
    Path source, {
    required double dash,
    required double gap,
  }) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final next = distance + (draw ? dash : gap);
        if (draw) {
          out.addPath(
            metric.extractPath(distance, next.clamp(0.0, metric.length)),
            Offset.zero,
          );
        }
        distance = next;
        draw = !draw;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant TransformEdgePainter old) =>
      old.version != version ||
      !listEquals(old.edges, edges) ||
      !mapEquals(old.nodeRects, nodeRects) ||
      !setEquals(old.activeEdges, activeEdges);
}
