import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_voices.dart';

/// The `.matrixctrl` object drawn as **only itself**: a grid of [columns] by
/// [rows] cells, each filled from the bottom to its value in the voice colour
/// (issue #474).
///
/// An on/off grid's cells are therefore empty or full; a stepped one's show
/// their level. The cells share the node's box equally, so a grid of any size
/// fits the box it was given, and one too dense to separate its cells draws
/// them edge to edge.
///
/// Visual-only: the toggle, paint and step gestures belong to the caller, so
/// the grid stays inert chrome while the canvas is in edit mode (issue #378).
class PatchMatrixGrid extends StatelessWidget {
  const PatchMatrixGrid({
    required this.columns,
    required this.rows,
    required this.values,
    required this.voice,
    super.key,
  });

  /// How many columns the grid has, left to right.
  final int columns;

  /// How many rows the grid has, top to bottom.
  final int rows;

  /// Each cell's value as a 0–1 position (0 empty, 1 full), **column-major**
  /// as the engine flattens it: cell (`c`, `r`) is `values[c * rows + r]`. A
  /// cell past the end of the list draws empty.
  final List<double> values;

  /// Voice index in `[1, 6]`; the filled cells take its colour.
  final int voice;

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
        painter: _GridPainter(
          columns: columns,
          rows: rows,
          values: values,
          color: PhiVoices.color(voice),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.columns,
    required this.rows,
    required this.values,
    required this.color,
  });

  final int columns;
  final int rows;
  final List<double> values;
  final Color color;

  /// Gap between neighbouring cells, when they are big enough to afford one.
  static const double _gap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || columns <= 0 || rows <= 0) return;
    final width = size.width / columns;
    final height = size.height / rows;
    final gap = width > 3 * _gap && height > 3 * _gap ? _gap : 0.0;
    final empty = Paint()..color = PhiColors.bg2;
    final fill = Paint()..color = color;
    for (var c = 0; c < columns; c++) {
      final left = c * width + gap / 2;
      final right = (c + 1) * width - gap / 2;
      for (var r = 0; r < rows; r++) {
        final top = r * height + gap / 2;
        final bottom = (r + 1) * height - gap / 2;
        if (gap > 0) {
          canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), empty);
        }
        final i = c * rows + r;
        final v = i < values.length ? values[i].clamp(0.0, 1.0) : 0.0;
        if (v <= 0) continue;
        final y = bottom - (bottom - top) * v;
        canvas.drawRect(Rect.fromLTRB(left, y, right, bottom), fill);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.columns != columns ||
      oldDelegate.rows != rows ||
      oldDelegate.color != color ||
      !listEquals(oldDelegate.values, values);
}
