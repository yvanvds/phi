import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_caret.dart';
import 'piano_roll_geometry.dart';
import 'piano_roll_view.dart';

/// Custom-painted piano roll. Renders pitch lanes, beat grid, the transformed
/// **ghost** layer (what the chain produces), the editable **source** layer on
/// top, the current selection highlight, and a marquee rectangle.
///
/// Pitch range is fixed to `[minPitch, maxPitch]`; notes outside the window
/// paint at the clamp boundary so an over-transposed transform still shows
/// *something*. The editor clamps edits to the same window so authored notes
/// stay on-screen.
class PianoRollPainter extends CustomPainter {
  PianoRollPainter({
    required this.sourceNotes,
    required this.ghostNotes,
    required this.selection,
    required this.bars,
    required this.beatsPerBar,
    required this.revision,
    this.marquee,
    this.showGhost = true,
    this.minPitch = 55,
    this.maxPitch = 76,
    this.playhead = 0,
    this.view,
    this.caret,
    this.caretLength = 0.25,
  });

  /// The editable clip notes — drawn bright, hit-tested by the gesture layer.
  final List<MidiNote> sourceNotes;

  /// The chain's transformed output — drawn dim behind the source.
  final List<MidiNote> ghostNotes;

  /// Indices into [sourceNotes] that are currently selected.
  final Set<int> selection;

  final int bars;
  final int beatsPerBar;

  /// Monotonic key from the editor/chain; see [shouldRepaint].
  final int revision;

  final Rect? marquee;
  final bool showGhost;
  final int minPitch;
  final int maxPitch;
  final double playhead;

  /// Session-local pan/zoom (issue #189). `null` paints the whole clip fitted to
  /// the area (the un-zoomed default); a view scales and offsets it.
  final PianoRollView? view;

  /// The step-entry caret (issue #191), or `null` when no caret is summoned. Drawn
  /// as an insertion cursor: a vertical guide at its beat and an outlined cell at
  /// its lane, [caretLength] beats wide (the note a drop would land).
  final PianoRollCaret? caret;

  /// The width of the caret's cell, in beats — the current grid step, so the
  /// preview cell matches the length `Enter` would drop.
  final double caretLength;

  static const Color _noteCore = PhiColors.voice1;
  static const Color _noteHalo = PhiColors.voice1Soft;
  static const Color _attackPip = PhiColors.fg0;
  static const Color _ghost = PhiColors.fg3;
  static const Color _selOutline = PhiColors.fg0;
  static const Color _caretColor = PhiColors.voice2;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = PianoRollGeometry(
      size: size,
      bars: bars,
      beatsPerBar: beatsPerBar,
      minPitch: minPitch,
      maxPitch: maxPitch,
      view: view,
    );

    _paintLanes(canvas, geo);
    _paintBeatGrid(canvas, geo);
    if (showGhost) _paintGhost(canvas, geo);
    _paintSource(canvas, geo);
    _paintMarquee(canvas);
    _paintPlayhead(canvas, geo);
    _paintCaret(canvas, geo);
  }

  void _paintLanes(Canvas canvas, PianoRollGeometry geo) {
    final faint = Paint()..color = PhiColors.grid;
    final strong = Paint()..color = PhiColors.gridStrong;
    for (var i = 0; i <= geo.pitchSpan; i++) {
      final pitch = maxPitch - i;
      final semitone = pitch % 12;
      final isKey = semitone == 0 || semitone == 7;
      final y = geo.laneLineY(i);
      canvas.drawLine(
        Offset(0, y),
        Offset(geo.size.width, y),
        isKey ? strong : faint,
      );
    }
  }

  void _paintBeatGrid(Canvas canvas, PianoRollGeometry geo) {
    final beat = Paint()..color = PhiColors.gridStrong;
    final sub = Paint()..color = PhiColors.grid;
    // Draw the sixteenth-note grid across the *visible* beat range, so a zoomed
    // roll still lines up on the pointer-anchored view (issue #189). Un-zoomed
    // this reduces to the old `beatSpan * 4` lines fitted to the width.
    const step = 0.25;
    final firstS = (geo.beatForX(0) / step).floor();
    final lastS = (geo.beatForX(geo.size.width) / step).ceil();
    for (var s = firstS; s <= lastS; s++) {
      if (s < 0) continue;
      final x = geo.xForBeat(s * step);
      final onBeat = s % 4 == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, geo.size.height),
        onBeat ? beat : sub,
      );
    }
  }

  void _paintGhost(Canvas canvas, PianoRollGeometry geo) {
    final paint = Paint()..color = _ghost.withValues(alpha: 0.5);
    for (final note in ghostNotes) {
      final y = geo.yForPitch(note.pitch);
      final x = geo.xForBeat(note.start);
      final w = geo.widthForBeats(note.duration);
      if (w <= 0) continue;
      canvas.drawRect(Rect.fromLTWH(x, y - 2, w, 4), paint);
    }
  }

  void _paintSource(Canvas canvas, PianoRollGeometry geo) {
    const haloMask = MaskFilter.blur(BlurStyle.normal, 2.4);
    final pip = Paint()..color = _attackPip;

    for (var i = 0; i < sourceNotes.length; i++) {
      final note = sourceNotes[i];
      final selected = selection.contains(i);
      final y = geo.yForPitch(note.pitch);
      final x = geo.xForBeat(note.start);
      final width = geo.widthForBeats(note.duration);
      if (width <= 0) continue;
      final coreAlpha = (0.6 + note.velocity * 0.4).clamp(0.0, 1.0);
      final haloAlpha = (0.4 + note.velocity * 0.4).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(x, y - 4, width, 8),
        Paint()
          ..color = _noteHalo.withValues(alpha: haloAlpha)
          ..maskFilter = haloMask,
      );
      canvas.drawRect(
        Rect.fromLTWH(x, y - 3, width, 6),
        Paint()
          ..color = _noteCore.withValues(alpha: selected ? 1.0 : coreAlpha),
      );
      if (selected) {
        canvas.drawRect(
          Rect.fromLTWH(x, y - 4, width, 8),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _selOutline,
        );
      }
      canvas.drawRect(Rect.fromLTWH(x, y - 1, 2, 2), pip);
    }
  }

  void _paintMarquee(Canvas canvas) {
    final rect = marquee;
    if (rect == null) return;
    canvas.drawRect(
      rect,
      Paint()..color = PhiColors.voice1.withValues(alpha: 0.10),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = PhiColors.voice1.withValues(alpha: 0.7),
    );
  }

  /// The step-entry caret: a full-height guide at its beat plus an outlined cell
  /// at its lane, [caretLength] beats wide — a preview of the note a drop lands.
  void _paintCaret(Canvas canvas, PianoRollGeometry geo) {
    final c = caret;
    if (c == null) return;
    final x = geo.xForBeat(c.beat);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, geo.size.height),
      Paint()
        ..color = _caretColor.withValues(alpha: 0.9)
        ..strokeWidth = 1.5,
    );
    final half = geo.laneHeight / 2;
    final y = geo.yForPitch(c.pitch.toDouble());
    final w = geo.widthForBeats(caretLength);
    canvas.drawRect(
      Rect.fromLTWH(x, y - half, w <= 0 ? 2 : w, geo.laneHeight),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _caretColor,
    );
  }

  void _paintPlayhead(Canvas canvas, PianoRollGeometry geo) {
    if (playhead <= 0) return;
    final x = geo.xForBeat(playhead);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, geo.size.height),
      Paint()..color = PhiColors.voice1.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant PianoRollPainter old) =>
      old.revision != revision ||
      old.bars != bars ||
      old.beatsPerBar != beatsPerBar ||
      old.minPitch != minPitch ||
      old.maxPitch != maxPitch ||
      old.showGhost != showGhost ||
      old.playhead != playhead ||
      old.view != view ||
      old.caret != caret ||
      old.caretLength != caretLength ||
      old.marquee != marquee ||
      !setEquals(old.selection, selection) ||
      !listEquals(old.sourceNotes, sourceNotes) ||
      !listEquals(old.ghostNotes, ghostNotes);
}
