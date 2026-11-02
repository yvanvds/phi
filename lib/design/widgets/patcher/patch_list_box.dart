import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import 'patch_canvas_constants.dart';

/// The `.l` object drawn as **only itself**: a box holding its stored list,
/// **notched at both ends** (issue #470).
///
/// A list box fires on a click like a message box, so it borrows the message
/// box's notch — and, being a different object, puts one on its left edge too,
/// a pair of brackets around the list rather than a single arrow out of it.
///
/// Visual-only: the press belongs to the caller ([child] is the list text).
class PatchListBox extends StatelessWidget {
  const PatchListBox({required this.child, super.key});

  /// The list text — laid out inside the shape, clear of both notches.
  final Widget child;

  /// Depth of each notch, as a fraction of the box's height.
  static const double notchFraction = 0.3;

  /// Width a list box opens at, and keeps until it is resized — the width of a
  /// message box, about ten characters of list.
  static const double defaultWidth = 96;

  /// Narrowest a right-edge resize takes a list box (issue #533).
  static const double minWidth = 48;

  /// Widest a right-edge resize takes a list box (issue #533).
  static const double maxWidth = 640;

  /// [width] held to [minWidth]–[maxWidth], in whole pixels.
  static double clampWidth(double width) =>
      width.clamp(minWidth, maxWidth).roundToDouble();

  /// The width a list box with a stored [width] (`w`, null when it was never
  /// resized) is drawn at — so a patch saved before list boxes could be
  /// resized opens them at [defaultWidth], as it always did.
  static double widthFor(double? width) =>
      width == null ? defaultWidth : clampWidth(width);

  /// The box's outline at [size]: a rectangle with a notch cut into each of
  /// its vertical edges. Public for the same reason the number and message
  /// boxes expose theirs — the shape is what the widget is for.
  static Path outlineFor(Size size) {
    final notch = size.height * notchFraction;
    const half = PatchCanvasConstants.nodeBorderWidth / 2;
    final right = size.width - half;
    final mid = size.height / 2;
    return Path()
      ..moveTo(half, half)
      ..lineTo(right, half)
      ..lineTo(right - notch, mid)
      ..lineTo(right, size.height - half)
      ..lineTo(half, size.height - half)
      ..lineTo(half + notch, mid)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _ListBoxPainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PatchCanvasConstants.objectBoxPaddingH * 2,
          PatchCanvasConstants.objectBoxPaddingV,
          PatchCanvasConstants.objectBoxPaddingH * 2,
          PatchCanvasConstants.objectBoxPaddingV,
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _ListBoxPainter extends CustomPainter {
  const _ListBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = PatchListBox.outlineFor(size);
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
  bool shouldRepaint(_ListBoxPainter oldDelegate) => false;
}
