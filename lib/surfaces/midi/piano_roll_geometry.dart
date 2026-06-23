import 'dart:ui';

import '../../domain/midi/midi_note.dart';

/// Which part of a note a pointer landed on — drives the drag gesture.
enum NoteEdge { left, body, right }

/// Result of a hit-test: the note's index plus the zone the pointer hit.
class NoteHit {
  const NoteHit(this.index, this.edge);
  final int index;
  final NoteEdge edge;
}

/// Pure pixel ↔ (pitch, beat) mapping for one piano-roll paint area.
///
/// Both [PianoRollPainter] and the gesture layer go through this so a note
/// is drawn and hit-tested with the exact same arithmetic — the classic
/// source of "I clicked the note but nothing happened" drift.
class PianoRollGeometry {
  const PianoRollGeometry({
    required this.size,
    required this.bars,
    required this.beatsPerBar,
    this.minPitch = 55,
    this.maxPitch = 76,
  });

  final Size size;
  final int bars;
  final int beatsPerBar;
  final int minPitch;
  final int maxPitch;

  int get beatSpan {
    final span = bars * beatsPerBar;
    return span <= 0 ? 1 : span;
  }

  int get pitchSpan => (maxPitch - minPitch).clamp(1, 127);

  double get laneHeight => size.height / pitchSpan;

  double xForBeat(double beat) => (beat / beatSpan) * size.width;

  double beatForX(double x) => (x / size.width) * beatSpan;

  double widthForBeats(double beats) => (beats / beatSpan) * size.width;

  /// Y of the lane *line* for [pitch] (notes are drawn centred on it).
  double yForPitch(int pitch) {
    final clamped = pitch.clamp(minPitch, maxPitch);
    return ((maxPitch - clamped) / pitchSpan) * size.height;
  }

  int pitchForY(double y) =>
      (maxPitch - (y / laneHeight).round()).clamp(minPitch, maxPitch);

  /// The clickable band for a note — a full lane-height row so thin notes
  /// stay grabbable, never narrower than [_minHitWidth].
  Rect hitRect(MidiNote note) {
    final x = xForBeat(note.start);
    final w = widthForBeats(note.duration);
    final y = yForPitch(note.pitch);
    final half = laneHeight / 2;
    return Rect.fromLTWH(
      x,
      y - half,
      w < _minHitWidth ? _minHitWidth : w,
      laneHeight,
    );
  }

  /// Topmost note under [point] (last-drawn wins), or null. The edge zones
  /// scale with note width but stay within `[3, 8]` px.
  NoteHit? hitTest(List<MidiNote> notes, Offset point) {
    for (var i = notes.length - 1; i >= 0; i--) {
      final r = hitRect(notes[i]);
      if (!r.contains(point)) continue;
      final tol = (r.width * 0.25).clamp(3.0, 8.0);
      final NoteEdge edge;
      if (point.dx <= r.left + tol) {
        edge = NoteEdge.left;
      } else if (point.dx >= r.right - tol) {
        edge = NoteEdge.right;
      } else {
        edge = NoteEdge.body;
      }
      return NoteHit(i, edge);
    }
    return null;
  }

  static const double _minHitWidth = 6;
}
