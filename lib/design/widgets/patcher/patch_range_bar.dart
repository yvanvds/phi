import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_voices.dart';

/// The `.rslider` object drawn as **only itself**: a vertical track — upright
/// like the `.slider` fader beside it, low end at the bottom — with the held
/// range filled in the voice colour between two bright end caps (issue #472).
///
/// The bar fills the node, so a resized `.rslider` is a longer throw rather
/// than a fixed bar floating in a box.
///
/// Visual-only: the drag belongs to the caller, so the bar stays inert chrome
/// while the canvas is in edit mode (issue #378).
class PatchRangeBar extends StatelessWidget {
  const PatchRangeBar({
    required this.low,
    required this.high,
    required this.voice,
    super.key,
  });

  /// The lower end, as a 0–1 position along the bar (0 at the bottom).
  final double low;

  /// The upper end, as a 0–1 position along the bar.
  final double high;

  /// Voice index in `[1, 6]`; the range takes its colour.
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
        painter: _RangePainter(
          low: low.clamp(0.0, 1.0),
          high: high.clamp(0.0, 1.0),
          color: PhiVoices.color(voice),
          glow: PhiVoices.glow(voice),
        ),
      ),
    );
  }
}

class _RangePainter extends CustomPainter {
  const _RangePainter({
    required this.low,
    required this.high,
    required this.color,
    required this.glow,
  });

  final double low;
  final double high;
  final Color color;
  final Color glow;

  /// Inset of the range from the track's sides, so the border stays visible.
  static const double _inset = 4;

  /// Thickness of an end cap.
  static const double _cap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final top = (1 - high) * size.height;
    final bottom = (1 - low) * size.height;
    final span = Rect.fromLTRB(_inset, top, size.width - _inset, bottom);
    canvas
      ..drawRect(
        span,
        Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawRect(span, Paint()..color = color.withValues(alpha: 0.55));
    final cap = Paint()..color = PhiColors.fg0;
    for (final y in [top, bottom]) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(
            size.width / 2,
            y.clamp(_cap / 2, size.height - _cap / 2),
          ),
          width: size.width - 2 * _inset,
          height: _cap,
        ),
        cap,
      );
    }
  }

  @override
  bool shouldRepaint(_RangePainter oldDelegate) =>
      oldDelegate.low != low ||
      oldDelegate.high != high ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
