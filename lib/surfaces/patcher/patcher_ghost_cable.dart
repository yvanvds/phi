import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../domain/patcher/patch_port_kind.dart';

/// In-flight cable drawn while the user drags from an output port toward
/// a (yet-unknown) target. The head follows the pointer; the tail anchors
/// at the source port. Coloured by the source outlet's data type ([color]),
/// dashed when it carries control-rate messages — matching the rendered cable.
class PatcherGhostCable extends StatelessWidget {
  const PatcherGhostCable({
    required this.source,
    required this.cursor,
    required this.color,
    required this.glow,
    required this.kind,
    super.key,
  });

  final Offset source;
  final Offset cursor;
  final Color color;
  final Color glow;
  final PatchPortKind kind;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GhostPainter(
          source: source,
          cursor: cursor,
          color: color,
          glow: glow,
          kind: kind,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.source,
    required this.cursor,
    required this.color,
    required this.glow,
    required this.kind,
  });

  final Offset source;
  final Offset cursor;
  final Color color;
  final Color glow;
  final PatchPortKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    const cx = PatchCanvasConstants.cableControlOffset;
    final path = Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(
        source.dx + cx,
        source.dy,
        cursor.dx - cx,
        cursor.dy,
        cursor.dx,
        cursor.dy,
      );

    canvas.drawPath(
      path,
      Paint()
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    final core = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    if (kind == PatchPortKind.control) {
      canvas.drawPath(_dashed(path, dash: 4, gap: 3), core);
    } else {
      canvas.drawPath(path, core);
    }
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
      old.cursor != cursor || old.source != source || old.color != color;
}
