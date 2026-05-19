import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import 'patch_canvas_constants.dart';

/// Backdrop dot grid for the patcher canvas — matches the design system's
/// 16px scope backdrop (see `design system/preview/spacing-grid.html`).
///
/// Paints small dots on a `gridCell` lattice and stronger dots on the
/// `gridMajor` lattice for visual anchoring during pan/zoom.
class PatchGridPainter extends CustomPainter {
  const PatchGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = PhiColors.grid;
    final dotMajor = Paint()..color = PhiColors.gridStrong;

    const cell = PatchCanvasConstants.gridCell;
    const major = PatchCanvasConstants.gridMajor;
    const r = 1.0;

    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final isMajor = (x % major == 0) && (y % major == 0);
        canvas.drawCircle(Offset(x, y), r, isMajor ? dotMajor : dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PatchGridPainter oldDelegate) => false;
}
