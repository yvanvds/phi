import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../domain/patcher/patch_port_kind.dart';

/// In-flight cable drawn while the user drags between a fixed port and a
/// (yet-unknown) one. The head follows the pointer; the tail anchors at
/// [source]. Coloured by the anchored port's data type ([color]), dashed when
/// it carries control-rate messages — matching the rendered cable.
///
/// A cable may be dragged from either end (issue #359). [backwards] says the
/// anchor is an *inlet* and the free end is looking for an outlet, which flips
/// the cubic's control points so the wire still leaves each end vertically
/// outward — down from an outlet, up from an inlet (#377) — instead of doubling
/// back on itself.
class PatcherGhostCable extends StatelessWidget {
  const PatcherGhostCable({
    required this.source,
    required this.cursor,
    required this.color,
    required this.glow,
    required this.kind,
    this.backwards = false,
    super.key,
  });

  final Offset source;
  final Offset cursor;
  final Color color;
  final Color glow;
  final PatchPortKind kind;

  /// Whether [source] is the cable's *target* inlet rather than its outlet.
  final bool backwards;

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
          backwards: backwards,
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
    required this.backwards,
  });

  final Offset source;
  final Offset cursor;
  final Color color;
  final Color glow;
  final PatchPortKind kind;
  final bool backwards;

  @override
  void paint(Canvas canvas, Size size) {
    // Down out of an anchored outlet, up out of an anchored inlet — the same
    // axis the finished cable uses (#377).
    final cy = backwards
        ? -PatchCanvasConstants.cableControlOffset
        : PatchCanvasConstants.cableControlOffset;
    final path = Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(
        source.dx,
        source.dy + cy,
        cursor.dx,
        cursor.dy - cy,
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
      old.cursor != cursor ||
      old.source != source ||
      old.color != color ||
      old.backwards != backwards;
}
