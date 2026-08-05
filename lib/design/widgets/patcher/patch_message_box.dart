import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import 'patch_canvas_constants.dart';

/// The `.m` object drawn as **only itself**: the message box, whose
/// **flag-shaped right edge** is the shape that says "message" (design §7, issue
/// #381).
///
/// What it replaces was a `MESSAGE` header over a bordered line inside a 120×66
/// frame. Max distinguishes a message box from a number box ([PatchNumberBox])
/// by its outline alone — the right edge is notched inwards, so the box reads as
/// a little flag — and with the headers gone that is exactly the job the outline
/// has to do here too.
///
/// Visual-only: the tap that fires the message is the caller's.
class PatchMessageBox extends StatelessWidget {
  const PatchMessageBox({required this.child, super.key});

  /// The message text — laid out inside the shape, clear of the notch.
  final Widget child;

  /// Depth of the right edge's notch, as a fraction of the box's height.
  static const double notchFraction = 0.3;

  /// The box's outline at [size] — the shape that says "message": a rectangle
  /// whose **right edge is notched inwards** to a point, so the box reads as a
  /// little flag.
  ///
  /// Public for the same reason [PatchNumberBox.outlineFor] is: the shape is
  /// what the widget is for, and `Path.contains` asserts it directly.
  static Path outlineFor(Size size) {
    final notch = size.height * notchFraction;
    const half = PatchCanvasConstants.nodeBorderWidth / 2;
    final right = size.width - half;
    return Path()
      ..moveTo(half, half)
      ..lineTo(right, half)
      ..lineTo(right - notch, size.height / 2)
      ..lineTo(right, size.height - half)
      ..lineTo(half, size.height - half)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _MessageBoxPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PatchCanvasConstants.objectBoxPaddingH,
          PatchCanvasConstants.objectBoxPaddingV,
          // Room for the notch, so the text never runs into it.
          PatchCanvasConstants.objectBoxPaddingH * 2,
          PatchCanvasConstants.objectBoxPaddingV,
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _MessageBoxPainter extends CustomPainter {
  const _MessageBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = PatchMessageBox.outlineFor(size);
    canvas
      ..drawPath(path, Paint()..color = PhiColors.bg1)
      ..drawPath(
        path,
        Paint()
          ..color = PhiColors.line2
          ..style = PaintingStyle.stroke
          ..strokeWidth = PatchCanvasConstants.nodeBorderWidth,
      );
  }

  @override
  bool shouldRepaint(_MessageBoxPainter oldDelegate) => false;
}
