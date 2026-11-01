import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/patcher/preset_grid.dart';
import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';

/// The `.preset` object drawn as **only itself**: a grid of [slots] buttons,
/// slot 0 at the top left, laid out by [PresetGrid] (issue #477).
///
/// The three states read apart at a glance: an empty slot is a dim cell, a
/// stored one is filled with the voice glow and ringed in the voice colour,
/// and the active one — the slot last stored or recalled — is filled solid in
/// the voice colour. Slot numbers are printed when the cells are big enough
/// to hold them.
///
/// Visual-only: the recall / store / clear click belongs to the caller, so the
/// grid stays inert chrome while the canvas is in edit mode (issue #378).
class PatchPresetGrid extends StatelessWidget {
  const PatchPresetGrid({
    required this.slots,
    required this.stored,
    required this.active,
    required this.voice,
    super.key,
  });

  /// How many slots the bank holds.
  final int slots;

  /// The slots that hold a snapshot.
  final Set<int> stored;

  /// The active slot, or -1 for none.
  final int active;

  /// Voice index in `[1, 6]`; stored and active slots take its colour.
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
        painter: _PresetPainter(
          slots: slots,
          stored: stored,
          active: active,
          color: PhiVoices.color(voice),
          glow: PhiVoices.glow(voice),
        ),
      ),
    );
  }
}

class _PresetPainter extends CustomPainter {
  const _PresetPainter({
    required this.slots,
    required this.stored,
    required this.active,
    required this.color,
    required this.glow,
  });

  final int slots;
  final Set<int> stored;
  final int active;
  final Color color;
  final Color glow;

  /// Inset of each slot inside its cell, when the cell can afford one.
  static const double _inset = 1.5;

  /// The smallest cell side that still prints its slot number.
  static const double _numberedSide = 16;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || slots <= 0) return;
    final grid = PresetGrid(
      slots: slots,
      width: size.width,
      height: size.height,
    );
    final w = grid.cellWidth;
    final h = grid.cellHeight;
    final inset = w > 4 * _inset && h > 4 * _inset ? _inset : 0.0;
    final numbered = w >= _numberedSide && h >= _numberedSide;
    final empty = Paint()..color = PhiColors.bg2;
    final glowFill = Paint()..color = glow;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final solid = Paint()..color = color;
    for (var slot = 0; slot < slots; slot++) {
      final (x, y) = grid.originOf(slot);
      final rect = Rect.fromLTWH(x, y, w, h).deflate(inset);
      final cell = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      final isActive = slot == active;
      final isStored = stored.contains(slot);
      if (isActive) {
        canvas.drawRRect(cell, solid);
      } else if (isStored) {
        canvas
          ..drawRRect(cell, glowFill)
          ..drawRRect(cell.deflate(0.5), ring);
      } else {
        canvas.drawRRect(cell, empty);
      }
      if (numbered) _number(canvas, rect, slot, isActive, isStored);
    }
  }

  void _number(Canvas canvas, Rect rect, int slot, bool on, bool stored) {
    final painter = TextPainter(
      text: TextSpan(
        text: '$slot',
        style: PhiType.monoS().copyWith(
          color: on
              ? PhiColors.bg0
              : stored
              ? PhiColors.fg0
              : PhiColors.fg3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width);
    if (painter.height > rect.height) {
      painter.dispose();
      return;
    }
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_PresetPainter oldDelegate) =>
      oldDelegate.slots != slots ||
      oldDelegate.active != active ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow ||
      !setEquals(oldDelegate.stored, stored);
}
