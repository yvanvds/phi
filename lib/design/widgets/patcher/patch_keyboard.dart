import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/midi/midi_pitch.dart';
import '../../../domain/patcher/keyboard_layout.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_voices.dart';

/// The `.kslider` object drawn as **only itself**: a horizontal piano keyboard
/// over [layout]'s range, each held key lit in the voice colour — brighter the
/// harder it was struck (issue #473).
///
/// The keys stretch to the node, laid out by [KeyboardLayout] so the drawing
/// and the caller's hit test agree on every key.
///
/// Visual-only: the press belongs to the caller, so the keyboard stays inert
/// chrome while the canvas is in edit mode (issue #378).
class PatchKeyboard extends StatelessWidget {
  const PatchKeyboard({
    required this.layout,
    required this.held,
    required this.voice,
    super.key,
  });

  /// The keys shown.
  final KeyboardLayout layout;

  /// Held keys: pitch → velocity (1–127). A key absent here is up.
  final Map<int, int> held;

  /// Voice index in `[1, 6]`; held keys take its colour.
  final int voice;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: PhiRadii.all2,
      child: CustomPaint(
        size: Size.infinite,
        painter: _KeyboardPainter(
          layout: layout,
          held: held,
          color: PhiVoices.color(voice),
        ),
      ),
    );
  }
}

class _KeyboardPainter extends CustomPainter {
  const _KeyboardPainter({
    required this.layout,
    required this.held,
    required this.color,
  });

  final KeyboardLayout layout;
  final Map<int, int> held;
  final Color color;

  Rect _rectOf(int pitch, Size size) {
    final b = layout.boundsOf(pitch);
    return Rect.fromLTRB(
      b.left * size.width,
      0,
      b.right * size.width,
      b.bottom * size.height,
    );
  }

  /// A held key's fill: the voice colour, fainter for a softer note.
  Color _litFor(int velocity) => color.withValues(
    alpha: 0.45 + 0.55 * (velocity / MidiPitch.maxVelocity).clamp(0.0, 1.0),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final seam = Paint()
      ..color = PhiColors.bg0
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final pitch in layout.pitches) {
      if (MidiPitch.isBlack(pitch)) continue;
      final rect = _rectOf(pitch, size);
      final velocity = held[pitch];
      canvas
        ..drawRect(
          rect,
          Paint()..color = velocity == null ? PhiColors.fg1 : _litFor(velocity),
        )
        ..drawRect(rect, seam);
    }
    for (final pitch in layout.pitches) {
      if (!MidiPitch.isBlack(pitch)) continue;
      final rect = _rectOf(pitch, size);
      final velocity = held[pitch];
      canvas.drawRect(
        rect,
        Paint()..color = velocity == null ? PhiColors.bg2 : _litFor(velocity),
      );
    }
    // Middle C carries a small tick, the one landmark a keyboard needs.
    if (layout.shows(MidiPitch.middleC)) {
      final c = _rectOf(MidiPitch.middleC, size);
      canvas.drawCircle(
        Offset(c.center.dx, c.bottom - 5),
        1.5,
        Paint()..color = PhiColors.fg3,
      );
    }
  }

  @override
  bool shouldRepaint(_KeyboardPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.layout.low != layout.low ||
      oldDelegate.layout.high != layout.high ||
      !mapEquals(oldDelegate.held, held);
}
