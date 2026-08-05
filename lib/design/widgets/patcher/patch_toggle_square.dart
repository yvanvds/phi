import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_voices.dart';

/// The `.t` object drawn as **only itself**: a square that carries a cross when
/// it is on (design §7, issue #381).
///
/// What it replaces was a `TOGGLE` header over a 38×18 pill inside a 90×80
/// frame. Max's square-with-a-mark is what a patcher toggle looks like, and at a
/// patcher's scale it also reads at a glance across a canvas full of them — the
/// pill belongs in the app's panels, where there is room for a label beside it.
///
/// Visual-only: the tap belongs to the caller, so the switch stays inert chrome
/// while the canvas is in edit mode (issue #378).
class PatchToggleSquare extends StatelessWidget {
  const PatchToggleSquare({
    required this.value,
    required this.voice,
    super.key,
  });

  /// Whether the toggle is on — the cross is drawn only then.
  final bool value;

  /// Voice index in `[1, 6]`; the cross takes the voice colour.
  final int voice;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(
          color: value ? PhiVoices.color(voice) : PhiColors.line2,
        ),
        boxShadow: value
            ? [BoxShadow(color: PhiVoices.glow(voice), blurRadius: 10)]
            : null,
      ),
      child: value
          ? CustomPaint(painter: _CrossPainter(PhiVoices.color(voice)))
          : null,
    );
  }
}

/// The toggle's mark: two strokes corner to corner, inset so they never touch
/// the border they sit inside.
class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);

  final Color color;

  /// Distance from each edge the cross starts at, as a fraction of the square.
  static const double _inset = 0.24;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = size.width * _inset;
    final dy = size.height * _inset;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(dx, dy),
        Offset(size.width - dx, size.height - dy),
        paint,
      )
      ..drawLine(
        Offset(size.width - dx, dy),
        Offset(dx, size.height - dy),
        paint,
      );
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) => oldDelegate.color != color;
}
