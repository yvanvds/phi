import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/midi_note.dart';
import 'piano_roll_geometry.dart';

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

  static const Color _noteCore = PhiColors.voice1;
  static const Color _noteHalo = PhiColors.voice1Soft;
  static const Color _attackPip = PhiColors.fg0;
  static const Color _ghost = PhiColors.fg3;
  static const Color _selOutline = PhiColors.fg0;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = PianoRollGeometry(
      size: size,
      bars: bars,
      beatsPerBar: beatsPerBar,
      minPitch: minPitch,
      maxPitch: maxPitch,
    );

    _paintLanes(canvas, geo);
    _paintBeatGrid(canvas, geo);
    if (showGhost) _paintGhost(canvas, geo);
    _paintSource(canvas, geo);
    _paintMarquee(canvas);
    _paintPlayhead(canvas, geo);
  }

  void _paintLanes(Canvas canvas, PianoRollGeometry geo) {
    final faint = Paint()..color = PhiColors.grid;
    final strong = Paint()..color = PhiColors.gridStrong;
    for (var i = 0; i <= geo.pitchSpan; i++) {
      final pitch = maxPitch - i;
      final semitone = pitch % 12;
      final isKey = semitone == 0 || semitone == 7;
      final y = geo.laneHeight * i;
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
    final subdivisions = geo.beatSpan * 4;
    for (var i = 0; i <= subdivisions; i++) {
      final x = (geo.size.width / subdivisions) * i;
      final onBeat = i % 4 == 0;
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
      old.marquee != marquee ||
      !setEquals(old.selection, selection) ||
      !listEquals(old.sourceNotes, sourceNotes) ||
      !listEquals(old.ghostNotes, ghostNotes);
}
