import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../domain/state_machine/performance_state_id.dart';
import '../../../domain/state_machine/state_transition.dart';
import '../../tokens/phi_colors.dart';
import 'state_canvas_constants.dart';

/// Painter for the directed transition arrows between state nodes.
///
/// Each [StateTransition] is drawn as a cubic Bézier between the
/// horizontal midpoints of the source and target node rects, with an
/// arrowhead at the target. Endpoints are clipped onto the source/target
/// node's right/left edge respectively so the arrow doesn't disappear
/// inside the node. Skips any transition whose endpoints are missing.
class StateTransitionPainter extends CustomPainter {
  StateTransitionPainter({
    required this.transitions,
    required this.nodeRects,
    required this.version,
  });

  /// Transitions to draw, in order.
  final List<StateTransition> transitions;

  /// Canvas-local rectangle of every state node currently rendered. The
  /// painter silently skips any transition referencing a missing endpoint.
  final Map<PerformanceStateId, Rect> nodeRects;

  /// Bumped whenever the graph changes — used by [shouldRepaint] as a
  /// cheap int comparison instead of deep-equals.
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = PhiColors.fg2
      ..style = PaintingStyle.stroke
      ..strokeWidth = StateCanvasConstants.transitionStroke;
    final fill = Paint()
      ..color = PhiColors.fg2
      ..style = PaintingStyle.fill;

    for (final t in transitions) {
      final src = nodeRects[t.sourceId];
      final dst = nodeRects[t.targetId];
      if (src == null || dst == null) continue;
      _drawTransition(canvas, src, dst, stroke, fill);
    }
  }

  static void _drawTransition(
    Canvas canvas,
    Rect src,
    Rect dst,
    Paint stroke,
    Paint fill,
  ) {
    // Endpoints picked on whichever side of the source faces the target.
    // Keeps arrows from running through their source node when the
    // performer drags a target above or below.
    final (a, b) = _pickEdges(src, dst);
    const cx = StateCanvasConstants.transitionControlOffset;
    final goingRight = b.dx >= a.dx;
    final c1 = Offset(a.dx + (goingRight ? cx : -cx), a.dy);
    final c2 = Offset(b.dx + (goingRight ? -cx : cx), b.dy);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
    canvas.drawPath(path, stroke);
    _drawArrowHead(canvas, b, c2, fill);
  }

  static (Offset, Offset) _pickEdges(Rect src, Rect dst) {
    final srcMid = src.center;
    final dstMid = dst.center;
    final dstToTheRight = dstMid.dx >= srcMid.dx;
    final a = Offset(dstToTheRight ? src.right : src.left, srcMid.dy);
    final b = Offset(dstToTheRight ? dst.left : dst.right, dstMid.dy);
    return (a, b);
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
    // Perpendicular unit vector.
    final px = -uy;
    final py = ux;
    const head = StateCanvasConstants.arrowHeadLength;
    const half = StateCanvasConstants.arrowHeadHalfWidth;
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

  @override
  bool shouldRepaint(covariant StateTransitionPainter old) =>
      old.version != version;
}
