import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Shifts every note's pitch by a fixed number of semitones. Pitches that
/// would leave the 7-bit MIDI range clamp to `[0, 127]` rather than wrap —
/// the alternative (silent loss) would surprise more than it would help.
class TransposeTransform extends MidiTransform {
  const TransposeTransform({
    required this.semitones,
    required this.label,
    this.active = true,
  });

  final int semitones;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.pitch;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input
      .map((n) => n.copyWith(pitch: (n.pitch + semitones).clamp(0, 127)))
      .toList(growable: false);

  @override
  TransposeTransform copyWith({bool? active}) => TransposeTransform(
    semitones: semitones,
    label: label,
    active: active ?? this.active,
  );
}
