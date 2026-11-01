import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_voices.dart';

/// The `.multislider` object drawn as **only itself**: a bank of upright bars,
/// one per cell, each filled from the bottom to its value in the voice colour
/// (issue #472).
///
/// The bars share the node's width equally, so a bank that grows or shrinks —
/// a list of another length landing on the object — re-lays into the same box
/// rather than resizing it. A bank too dense to give every bar a gap draws
/// them edge to edge.
///
/// Visual-only: the drawing gesture belongs to the caller, so the bank stays
/// inert chrome while the canvas is in edit mode (issue #378).
class PatchSliderBank extends StatelessWidget {
  const PatchSliderBank({required this.values, required this.voice, super.key});

  /// Each cell's value as a 0–1 position (0 empty, 1 full), left to right.
  final List<double> values;

  /// Voice index in `[1, 6]`; the bars take its colour.
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
        painter: _BankPainter(values: values, color: PhiVoices.color(voice)),
      ),
    );
  }
}

class _BankPainter extends CustomPainter {
  const _BankPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  /// Gap between neighbouring bars, when they are wide enough to afford one.
  static const double _gap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.isEmpty) return;
    final width = size.width / values.length;
    final gap = width > 3 * _gap ? _gap : 0.0;
    final fill = Paint()..color = color.withValues(alpha: 0.8);
    final top = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final left = i * width + gap / 2;
      final right = (i + 1) * width - gap / 2;
      final y = (1 - v) * size.height;
      canvas.drawRect(Rect.fromLTRB(left, y, right, size.height), fill);
      canvas.drawRect(
        Rect.fromLTRB(left, y, right, (y + 2).clamp(0.0, size.height)),
        top,
      );
    }
  }

  @override
  bool shouldRepaint(_BankPainter oldDelegate) =>
      oldDelegate.color != color || !listEquals(oldDelegate.values, values);
}
