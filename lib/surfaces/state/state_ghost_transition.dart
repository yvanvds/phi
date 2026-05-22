import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/widgets/state_machine/state_canvas_constants.dart';

/// In-flight transition arrow drawn while the user drags from a state
/// node toward a (yet-unknown) target. The head follows the pointer; the
/// tail anchors at the source node centre. Dashed throughout to signal
/// "not yet committed".
class StateGhostTransition extends StatelessWidget {
  const StateGhostTransition({
    required this.source,
    required this.cursor,
    super.key,
  });

  final Offset source;
  final Offset cursor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GhostPainter(source: source, cursor: cursor),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter({required this.source, required this.cursor});

  final Offset source;
  final Offset cursor;

  @override
  void paint(Canvas canvas, Size size) {
    const cx = StateCanvasConstants.transitionControlOffset;
    final goingRight = cursor.dx >= source.dx;
    final c1Dx = source.dx + (goingRight ? cx : -cx);
    final c2Dx = cursor.dx + (goingRight ? -cx : cx);
    final path = Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(c1Dx, source.dy, c2Dx, cursor.dy, cursor.dx, cursor.dy);

    final stroke = Paint()
      ..color = PhiColors.fg2
      ..style = PaintingStyle.stroke
      ..strokeWidth = StateCanvasConstants.transitionStroke;

    canvas.drawPath(_dashed(path, dash: 4, gap: 3), stroke);
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
  bool shouldRepaint(covariant _GhostPainter old) =>
      old.cursor != cursor || old.source != source;
}
