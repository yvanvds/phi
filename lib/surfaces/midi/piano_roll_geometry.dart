import 'dart:ui';

import '../../domain/midi/midi_note.dart';
import 'piano_roll_view.dart';

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
    this.view,
  });

  final Size size;
  final int bars;
  final int beatsPerBar;
  final int minPitch;
  final int maxPitch;

  /// Session-local pan/zoom. When `null` the geometry fits the whole clip to the
  /// paint area (the un-zoomed default), so every existing consumer keeps its
  /// old arithmetic; a non-null view parametrises pixels-per-beat, lane-height
  /// and the scroll offsets instead (issue #189).
  final PianoRollView? view;

  int get beatSpan {
    final span = bars * beatsPerBar;
    return span <= 0 ? 1 : span;
  }

  int get pitchSpan => (maxPitch - minPitch).clamp(1, 127);

  /// Pixels one beat occupies — the view's zoom, or fit-to-width when un-zoomed.
  double get pixelsPerBeat => view?.pixelsPerBeat ?? (size.width / beatSpan);

  /// Pixels one semitone lane occupies — the view's zoom, or fit-to-height.
  double get laneHeight => view?.laneHeight ?? (size.height / pitchSpan);

  double get _originBeat => view?.scrollBeats ?? 0;
  double get _scrollLanes => view?.scrollLanes ?? 0;

  double xForBeat(double beat) => (beat - _originBeat) * pixelsPerBeat;

  double beatForX(double x) => _originBeat + x / pixelsPerBeat;

  double widthForBeats(double beats) => beats * pixelsPerBeat;

  /// Y of the horizontal grid line for lane index [i] (0 = [maxPitch]), the top
  /// edge of that lane's row — used by the painter to draw the pitch grid.
  double laneLineY(int i) => (i - _scrollLanes) * laneHeight;

  /// Y of the lane *line* for [pitch] (notes are drawn centred on it). A
  /// fractional pitch lands proportionally between two lanes, so a microtonal
  /// note draws slightly off the semitone grid (issue #36).
  double yForPitch(double pitch) {
    final clamped = pitch.clamp(minPitch.toDouble(), maxPitch.toDouble());
    return ((maxPitch - clamped) - _scrollLanes) * laneHeight;
  }

  /// The integer lane under [y]. Authoring snaps to whole semitones, so this
  /// deliberately rounds — fractional pitches come from transforms, not the
  /// pointer.
  int pitchForY(double y) => (maxPitch - _scrollLanes - y / laneHeight)
      .round()
      .clamp(minPitch, maxPitch);

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
