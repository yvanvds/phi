import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';

/// The `.dial` object drawn as **only itself**: a knob — a 270° track, the
/// voice-coloured arc up to the position, a pointer — with the value it sends
/// in the gap at its foot (design system `component-controls.html`, "knob";
/// issue #470).
///
/// Square by nature: the knob is the largest circle the node holds, so a
/// resized dial is a bigger knob rather than a stretched one.
///
/// Visual-only: the drag belongs to the caller, so the knob stays inert chrome
/// while the canvas is in edit mode (issue #378).
class PatchDialKnob extends StatelessWidget {
  const PatchDialKnob({
    required this.position,
    required this.readout,
    required this.voice,
    super.key,
  });

  /// Where the knob points, 0 (fully left) to 1 (fully right).
  final double position;

  /// The value the dial sends at [position], already formatted.
  final String readout;

  /// Voice index in `[1, 6]`; the arc and the pointer take its colour.
  final int voice;

  /// Where the sweep starts — down-left, 135° clockwise from three o'clock.
  static const double startAngle = 3 * math.pi / 4;

  /// How far the sweep runs, leaving the foot open for the readout.
  static const double sweepAngle = 3 * math.pi / 2;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KnobPainter(
        position: position.clamp(0.0, 1.0),
        color: PhiVoices.color(voice),
        glow: PhiVoices.glow(voice),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Text(
          readout,
          style: PhiType.monoS().copyWith(color: PhiColors.fg1, height: 1),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter({
    required this.position,
    required this.color,
    required this.glow,
  });

  final double position;
  final Color color;
  final Color glow;

  /// Track and arc stroke — the design card's 3px at 84px, kept at small
  /// sizes because a thinner arc stops reading on a dense canvas.
  static const double _stroke = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 - _stroke;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = PatchDialKnob.sweepAngle * position;

    canvas.drawArc(
      rect,
      PatchDialKnob.startAngle,
      PatchDialKnob.sweepAngle,
      false,
      Paint()
        ..color = PhiColors.line1
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );
    if (sweep > 0) {
      canvas
        ..drawArc(
          rect,
          PatchDialKnob.startAngle,
          sweep,
          false,
          Paint()
            ..color = glow
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke + 3
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        )
        ..drawArc(
          rect,
          PatchDialKnob.startAngle,
          sweep,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke
            ..strokeCap = StrokeCap.round,
        );
    }

    final angle = PatchDialKnob.startAngle + sweep;
    final tip =
        center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.7;
    canvas
      ..drawLine(
        center,
        tip,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(center, 2, Paint()..color = PhiColors.fg0);
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
