import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/midi/midi_note.dart';

/// Custom-painted piano roll. Renders pitch lanes, beat grid, magenta
/// notes with a soft halo, and a static playhead.
///
/// Pitch range is fixed to `[minPitch, maxPitch]` per the mockup; notes
/// outside the window paint at the clamp boundary so an over-transposed
/// transform still produces *something* the viewer can see.
class PianoRollPainter extends CustomPainter {
  PianoRollPainter({
    required this.notes,
    required this.bars,
    required this.beatsPerBar,
    required this.version,
    this.minPitch = 55,
    this.maxPitch = 76,
    this.playhead = 0,
  });

  final List<MidiNote> notes;
  final int bars;
  final int beatsPerBar;
  final int version;
  final int minPitch;
  final int maxPitch;
  final double playhead;

  static const Color _noteCore = PhiColors.voice1;
  static const Color _noteHalo = PhiColors.voice1Soft;
  static const Color _attackPip = PhiColors.fg0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pitchSpan = (maxPitch - minPitch).clamp(1, 127);
    final beatSpan = bars * beatsPerBar;

    _paintLanes(canvas, w, h, pitchSpan);
    _paintBeatGrid(canvas, w, h, beatSpan);
    _paintNotes(canvas, w, h, pitchSpan, beatSpan);
    _paintPlayhead(canvas, w, h, beatSpan);
  }

  void _paintLanes(Canvas canvas, double w, double h, int pitchSpan) {
    final faint = Paint()..color = const Color(0x06FFFFFF);
    final strong = Paint()..color = const Color(0x14FFFFFF);
    for (var i = 0; i <= pitchSpan; i++) {
      final pitch = maxPitch - i;
      final semitone = pitch % 12;
      final isKey = semitone == 0 || semitone == 7;
      final y = (h / pitchSpan) * i;
      canvas.drawLine(Offset(0, y), Offset(w, y), isKey ? strong : faint);
    }
  }

  void _paintBeatGrid(Canvas canvas, double w, double h, int beatSpan) {
    final beat = Paint()..color = const Color(0x14FFFFFF);
    final sub = Paint()..color = const Color(0x06FFFFFF);
    final subdivisions = beatSpan * 4;
    for (var i = 0; i <= subdivisions; i++) {
      final x = (w / subdivisions) * i;
      final onBeat = i % 4 == 0;
      canvas.drawLine(Offset(x, 0), Offset(x, h), onBeat ? beat : sub);
    }
  }

  void _paintNotes(
    Canvas canvas,
    double w,
    double h,
    int pitchSpan,
    int beatSpan,
  ) {
    const haloMask = MaskFilter.blur(BlurStyle.normal, 2.4);
    final pip = Paint()..color = _attackPip;

    for (final note in notes) {
      final clampedPitch = note.pitch.clamp(minPitch, maxPitch);
      final y = ((maxPitch - clampedPitch) / pitchSpan) * h;
      final x = (note.start / beatSpan) * w;
      final width = (note.duration / beatSpan) * w;
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
        Paint()..color = _noteCore.withValues(alpha: coreAlpha),
      );
      canvas.drawRect(Rect.fromLTWH(x, y - 1, 2, 2), pip);
    }
  }

  void _paintPlayhead(Canvas canvas, double w, double h, int beatSpan) {
    if (playhead <= 0) return;
    final x = (playhead / beatSpan) * w;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, h),
      Paint()..color = PhiColors.voice1.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant PianoRollPainter old) =>
      old.version != version ||
      old.bars != bars ||
      old.beatsPerBar != beatsPerBar ||
      old.minPitch != minPitch ||
      old.maxPitch != maxPitch ||
      old.playhead != playhead;
}
