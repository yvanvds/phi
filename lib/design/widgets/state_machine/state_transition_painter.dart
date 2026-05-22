import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../domain/state_machine/performance_state_id.dart';
import '../../../domain/state_machine/state_transition.dart';
import '../../tokens/phi_colors.dart';
import 'state_canvas_constants.dart';
import 'state_transition_geometry.dart';

/// Painter for the directed transition arrows between state nodes.
///
/// Each [StateTransition] is drawn as a cubic Bézier between the
/// horizontal midpoints of the source and target node rects, with an
/// arrowhead at the target. Endpoints are clipped onto the source/target
/// node's right/left edge respectively so the arrow doesn't disappear
/// inside the node. Armed transitions render in the hot fuchsia palette
/// to match the design-system preview; everything else uses the muted
/// foreground. Skips any transition whose endpoints are missing.
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
    final mutedStroke = Paint()
      ..color = PhiColors.fg2
      ..style = PaintingStyle.stroke
      ..strokeWidth = StateCanvasConstants.transitionStroke;
    final mutedFill = Paint()
      ..color = PhiColors.fg2
      ..style = PaintingStyle.fill;
    final hotStroke = Paint()
      ..color = PhiColors.live
      ..style = PaintingStyle.stroke
      ..strokeWidth = StateCanvasConstants.transitionStroke;
    final hotFill = Paint()
      ..color = PhiColors.live
      ..style = PaintingStyle.fill;

    for (final t in transitions) {
      final src = nodeRects[t.sourceId];
      final dst = nodeRects[t.targetId];
      if (src == null || dst == null) continue;
      final stroke = t.armed ? hotStroke : mutedStroke;
      final fill = t.armed ? hotFill : mutedFill;
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
    final curve = StateTransitionGeometry.curveBetween(src, dst);
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
    canvas.drawPath(path, stroke);
    _drawArrowHead(canvas, curve.b, curve.c2, fill);
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
