import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// The `.incdec` object drawn as **only itself**: a box holding the current
/// value, with an up and a down chevron stacked on its right — the stepper a
/// patcher draws (issue #470).
///
/// The whole top half of the box is "up" and the whole bottom half "down",
/// which the chevrons only *mark*: a target the full width of the node is the
/// one a quick click actually lands on. The half under the pointer lights in
/// the voice colour while it is held.
///
/// Visual-only: the press belongs to the caller ([pressed] reports it back),
/// so the stepper stays inert chrome while the canvas is in edit mode (issue
/// #378).
class PatchIncdecStepper extends StatelessWidget {
  const PatchIncdecStepper({
    required this.child,
    required this.voice,
    this.pressed,
    super.key,
  });

  /// The value readout, laid out left of the chevrons.
  final Widget child;

  /// Voice index in `[1, 6]`; the held half and its chevron take its colour.
  final int voice;

  /// The half being held — `true` up, `false` down, `null` neither.
  final bool? pressed;

  /// Width of the chevron column on the right.
  static const double chevronColumnWidth = 16;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StepperPainter(
        pressed: pressed,
        color: PhiVoices.color(voice),
        glow: PhiVoices.glow(voice),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PatchCanvasConstants.objectBoxPaddingH,
          PatchCanvasConstants.objectBoxPaddingV,
          chevronColumnWidth + PatchCanvasConstants.objectBoxPaddingH,
          PatchCanvasConstants.objectBoxPaddingV,
        ),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _StepperPainter extends CustomPainter {
  const _StepperPainter({
    required this.pressed,
    required this.color,
    required this.glow,
  });

  final bool? pressed;
  final Color color;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    const half = PatchCanvasConstants.nodeBorderWidth / 2;
    final box = Rect.fromLTRB(
      half,
      half,
      size.width - half,
      size.height - half,
    );
    final mid = size.height / 2;
    canvas.drawRect(box, Paint()..color = PhiColors.bg1);
    if (pressed != null) {
      canvas.drawRect(
        pressed!
            ? Rect.fromLTRB(box.left, box.top, box.right, mid)
            : Rect.fromLTRB(box.left, mid, box.right, box.bottom),
        Paint()..color = glow,
      );
    }
    canvas.drawRect(
      box,
      Paint()
        ..color = PhiColors.line2
        ..style = PaintingStyle.stroke
        ..strokeWidth = PatchCanvasConstants.nodeBorderWidth,
    );

    // The chevrons, centred in their column, one per half.
    final cx = size.width - PatchIncdecStepper.chevronColumnWidth / 2 - half;
    const reach = PatchIncdecStepper.chevronColumnWidth * 0.22;
    final rise = (mid * 0.28).clamp(1.5, 4.0);
    Paint stroke(bool lit) => Paint()
      ..color = lit ? color : PhiColors.fg2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final upY = mid / 2;
    final downY = mid + mid / 2;
    canvas
      ..drawPath(
        Path()
          ..moveTo(cx - reach, upY + rise / 2)
          ..lineTo(cx, upY - rise / 2)
          ..lineTo(cx + reach, upY + rise / 2),
        stroke(pressed == true),
      )
      ..drawPath(
        Path()
          ..moveTo(cx - reach, downY - rise / 2)
          ..lineTo(cx, downY + rise / 2)
          ..lineTo(cx + reach, downY - rise / 2),
        stroke(pressed == false),
      );
  }

  @override
  bool shouldRepaint(_StepperPainter oldDelegate) =>
      oldDelegate.pressed != pressed ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
