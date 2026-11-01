import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/patcher/function_point.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_voices.dart';

/// The `.function` object drawn as **only itself**: its breakpoints joined by
/// their segments, each bent by the curve it carries, in the voice colour
/// (issue #475).
///
/// Every point is a 0–1 position in the plot — x along the domain, y up the
/// range — inset by [inset] from the box so a point on the edge is still a
/// whole dot. The [selected] point is drawn filled and larger.
///
/// Visual-only: adding, moving, bending and removing belong to the caller, so
/// the graph stays inert chrome while the canvas is in edit mode (issue #378).
class PatchFunctionGraph extends StatelessWidget {
  const PatchFunctionGraph({
    required this.positions,
    required this.curves,
    required this.voice,
    this.selected,
    super.key,
  });

  /// The gap between the box's edge and the plot, in pixels, on every side.
  static const double inset = 6;

  /// Each point as (x, y) in 0–1, x left to right and y bottom to top, in
  /// ascending-x order.
  final List<(double, double)> positions;

  /// Each point's curve in [-1, 1], shaping the segment arriving at it.
  final List<double> curves;

  /// Voice index in `[1, 6]`; the line and points take its colour.
  final int voice;

  /// The point the editor has taken, if any.
  final int? selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _GraphPainter(
          positions: positions,
          curves: curves,
          selected: selected,
          color: PhiVoices.color(voice),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.positions,
    required this.curves,
    required this.selected,
    required this.color,
  });

  final List<(double, double)> positions;
  final List<double> curves;
  final int? selected;
  final Color color;

  /// Samples drawn along a curved segment; a straight one needs none.
  static const int _samples = 24;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = PatchFunctionGraph.inset;
    final width = size.width - 2 * inset;
    final height = size.height - 2 * inset;
    if (width <= 0 || height <= 0 || positions.isEmpty) return;
    Offset at(double x, double y) =>
        Offset(inset + x * width, inset + (1 - y) * height);

    final path = Path();
    final (x0, y0) = positions.first;
    path.moveTo(inset, at(x0, y0).dy);
    path.lineTo(at(x0, y0).dx, at(x0, y0).dy);
    for (var i = 1; i < positions.length; i++) {
      final (ax, ay) = positions[i - 1];
      final (bx, by) = positions[i];
      final c = i < curves.length ? curves[i] : 0.0;
      if (c == 0) {
        final p = at(bx, by);
        path.lineTo(p.dx, p.dy);
        continue;
      }
      for (var s = 1; s <= _samples; s++) {
        final t = s / _samples;
        final y = ay + FunctionPoint.shape(t, c) * (by - ay);
        final p = at(ax + t * (bx - ax), y);
        path.lineTo(p.dx, p.dy);
      }
    }
    final (xn, yn) = positions.last;
    path.lineTo(inset + width, at(xn, yn).dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final dot = Paint()..color = color;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final hole = Paint()..color = PhiColors.bg1;
    for (var i = 0; i < positions.length; i++) {
      final (x, y) = positions[i];
      final p = at(x, y);
      if (i == selected) {
        canvas.drawCircle(p, 4.5, dot);
      } else {
        canvas.drawCircle(p, 3, hole);
        canvas.drawCircle(p, 3, ring);
      }
    }
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      !listEquals(oldDelegate.positions, positions) ||
      !listEquals(oldDelegate.curves, curves);
}
