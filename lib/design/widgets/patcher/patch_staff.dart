import 'package:flutter/widgets.dart';

import '../../../domain/patcher/staff_note.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';

/// The `.nslider` object drawn as **only itself**: a treble-over-bass grand
/// staff with one note head on it, its accidental beside it, and an ottava mark
/// when the note sounds octaves away from where it is drawn (issue #473).
///
/// The staff stretches to the node: [StaffNote]'s step window fills the height.
///
/// Visual-only: the drag belongs to the caller, so the staff stays inert
/// chrome while the canvas is in edit mode (issue #378).
class PatchStaff extends StatelessWidget {
  const PatchStaff({required this.note, required this.voice, super.key});

  /// The note drawn.
  final StaffNote note;

  /// Voice index in `[1, 6]`; the note takes its colour.
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
        painter: _StaffPainter(note: note, color: PhiVoices.color(voice)),
      ),
    );
  }
}

class _StaffPainter extends CustomPainter {
  const _StaffPainter({required this.note, required this.color});

  final StaffNote note;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // One half-space per step, with a step of margin above and below.
    const steps = StaffNote.highStep - StaffNote.lowStep + 2;
    final half = size.height / steps;
    double yOf(int step) => (StaffNote.highStep + 1 - step) * half;

    final line = Paint()
      ..color = PhiColors.fg3
      ..strokeWidth = 1;
    final inset = size.width * 0.12;
    for (final step in [...StaffNote.bassLines, ...StaffNote.trebleLines]) {
      final y = yOf(step);
      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), line);
    }

    final headX = size.width * 0.58;
    final headW = half * 2.6;
    final y = yOf(note.step);
    final ink = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final step in note.ledgers) {
      final ly = yOf(step);
      canvas.drawLine(
        Offset(headX - headW * 0.85, ly),
        Offset(headX + headW * 0.85, ly),
        line,
      );
    }
    canvas
      ..save()
      ..translate(headX, y)
      ..rotate(-0.35)
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: headW, height: half * 1.8),
        Paint()..color = color,
      )
      ..restore();

    final ax = headX - headW * 1.3;
    if (note.accidental > 0) {
      _sharp(canvas, Offset(ax, y), half, ink);
    } else if (note.accidental < 0) {
      _flat(canvas, Offset(ax, y), half, ink);
    }

    if (note.ottava != 0) {
      final octaves = note.ottava.abs();
      final up = note.ottava > 0;
      final suffix = octaves == 1 ? (up ? 'va' : 'vb') : (up ? 'ma' : 'mb');
      final label = '${octaves * 7 + 1}$suffix';
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: PhiType.monoS().copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final ty = up ? 2.0 : size.height - text.height - 2;
      text.paint(canvas, Offset(size.width - text.width - 3, ty));
    }
  }

  /// A sharp centred on [at]: two uprights crossed by two rising bars.
  void _sharp(Canvas canvas, Offset at, double half, Paint ink) {
    final w = half * 0.9;
    final h = half * 2.6;
    for (final dx in [-w / 3, w / 3]) {
      canvas.drawLine(at + Offset(dx, -h / 2), at + Offset(dx, h / 2), ink);
    }
    for (final dy in [-half * 0.45, half * 0.45]) {
      canvas.drawLine(
        at + Offset(-w / 2, dy + half * 0.2),
        at + Offset(w / 2, dy - half * 0.2),
        ink,
      );
    }
  }

  /// A flat sitting on [at]: an upright with a bowl at its foot.
  void _flat(Canvas canvas, Offset at, double half, Paint ink) {
    final left = at.dx - half * 0.35;
    canvas.drawLine(
      Offset(left, at.dy - half * 2.4),
      Offset(left, at.dy + half * 0.9),
      ink,
    );
    final bowl = Path()
      ..moveTo(left, at.dy + half * 0.9)
      ..quadraticBezierTo(
        left + half * 1.3,
        at.dy - half * 0.2,
        left,
        at.dy - half * 0.2,
      );
    canvas.drawPath(bowl, ink);
  }

  @override
  bool shouldRepaint(_StaffPainter oldDelegate) =>
      oldDelegate.note != note || oldDelegate.color != color;
}
