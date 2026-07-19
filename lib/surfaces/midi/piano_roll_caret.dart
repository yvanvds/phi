import 'package:flutter/foundation.dart';

/// The piano-roll **step-entry caret** (design `docs/design/midi-clips.md` §5,
/// decision 3) — a beat-position edit cursor the arrow keys move by one grid
/// step. `Enter` drops a grid-length note at its lane/beat and advances it;
/// `Escape` dismisses it.
///
/// Immutable: a move produces a fresh instance the widget swaps in, mirroring
/// [PianoRollView]. Pure view state — never persisted, and `null` (no caret)
/// is the resting state until the roll's keyboard summons one.
@immutable
class PianoRollCaret {
  const PianoRollCaret({required this.beat, required this.pitch});

  /// The caret's position on the time axis, in beats (kept grid-aligned by the
  /// editor, which only ever moves it by whole grid steps from 0).
  final double beat;

  /// The caret's lane — a whole semitone, the pitch a dropped note takes.
  final int pitch;

  PianoRollCaret copyWith({double? beat, int? pitch}) =>
      PianoRollCaret(beat: beat ?? this.beat, pitch: pitch ?? this.pitch);

  @override
  bool operator ==(Object other) =>
      other is PianoRollCaret && other.beat == beat && other.pitch == pitch;

  @override
  int get hashCode => Object.hash(beat, pitch);

  @override
  String toString() => 'PianoRollCaret(beat: $beat, pitch: $pitch)';
}
