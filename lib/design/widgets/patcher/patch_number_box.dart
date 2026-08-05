import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import 'patch_canvas_constants.dart';

/// The `.i` / `.f` objects drawn as **only themselves**: a bare readout whose
/// **angled right edge** is the shape that says "number" (design §7, issue
/// #381).
///
/// What it replaces was a `NUMBER · F` header over a bordered readout inside a
/// 110×70 frame. With the header gone something still has to distinguish a
/// number box from a message box at a glance, and Max's answer is the outline
/// itself: a number box's top-right corner is cut away. That is a fact the shape
/// carries for free, on every box, at no cost in pixels or reading.
///
/// Visual-only: the readout, its focus, its keyboard and its scrub are the
/// caller's ([child]).
class PatchNumberBox extends StatelessWidget {
  const PatchNumberBox({required this.child, super.key});

  /// The readout — laid out inside the shape, clear of the cut corner.
  final Widget child;

  /// Depth of the corner cut, as a fraction of the box's height. Proportional
  /// rather than fixed so the shape stays recognisable whatever a number box is
  /// sized to.
  static const double cutFraction = 0.42;

  /// The box's outline at [size] — the shape that says "number": a rectangle
  /// with its **top-right corner cut away**.
  ///
  /// Public because the shape is the whole point of the widget, so it is the
  /// thing worth asserting: `Path.contains` answers whether a corner is inside
  /// the box far more directly than any pixel comparison would.
  static Path outlineFor(Size size) {
    final cut = size.height * cutFraction;
    const half = PatchCanvasConstants.nodeBorderWidth / 2;
    return Path()
      ..moveTo(half, half)
      ..lineTo(size.width - cut, half)
      ..lineTo(size.width - half, cut)
      ..lineTo(size.width - half, size.height - half)
      ..lineTo(half, size.height - half)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _NumberBoxPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PatchCanvasConstants.objectBoxPaddingH,
          PatchCanvasConstants.objectBoxPaddingV,
          // Room for the cut corner, so a long value never runs into it.
          PatchCanvasConstants.objectBoxPaddingH * 2,
          PatchCanvasConstants.objectBoxPaddingV,
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _NumberBoxPainter extends CustomPainter {
  const _NumberBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = PatchNumberBox.outlineFor(size);
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
  bool shouldRepaint(_NumberBoxPainter oldDelegate) => false;
}
