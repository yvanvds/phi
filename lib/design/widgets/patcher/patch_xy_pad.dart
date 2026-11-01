import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_voices.dart';

/// The `.xyslider` object drawn as **only itself**: a square pad with a
/// crosshair through a voice-coloured puck at the held position — x to the
/// right, y up, as on every fader in the patcher (issue #472).
///
/// The pad fills the node, so a resized `.xyslider` is a bigger surface.
///
/// Visual-only: the drag belongs to the caller, so the pad stays inert chrome
/// while the canvas is in edit mode (issue #378).
class PatchXyPad extends StatelessWidget {
  const PatchXyPad({
    required this.x,
    required this.y,
    required this.voice,
    super.key,
  });

  /// The puck's horizontal position, 0 (left) to 1 (right).
  final double x;

  /// The puck's vertical position, 0 (bottom) to 1 (top).
  final double y;

  /// Voice index in `[1, 6]`; the puck and crosshair take its colour.
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
        painter: _PadPainter(
          x: x.clamp(0.0, 1.0),
          y: y.clamp(0.0, 1.0),
          color: PhiVoices.color(voice),
          glow: PhiVoices.glow(voice),
        ),
      ),
    );
  }
}

class _PadPainter extends CustomPainter {
  const _PadPainter({
    required this.x,
    required this.y,
    required this.color,
    required this.glow,
  });

  final double x;
  final double y;
  final Color color;
  final Color glow;

  static const double _puckRadius = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final at = Offset(x * size.width, (1 - y) * size.height);
    final line = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset(at.dx, 0), Offset(at.dx, size.height), line)
      ..drawLine(Offset(0, at.dy), Offset(size.width, at.dy), line)
      ..drawCircle(
        at,
        _puckRadius + 3,
        Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawCircle(at, _puckRadius, Paint()..color = color)
      ..drawCircle(
        at,
        _puckRadius,
        Paint()
          ..color = PhiColors.fg0
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }

  @override
  bool shouldRepaint(_PadPainter oldDelegate) =>
      oldDelegate.x != x ||
      oldDelegate.y != y ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
