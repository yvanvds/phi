import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../transform_param.dart';

/// Shifts every note's pitch by a fixed number of semitones. Pitches that
/// would leave the 7-bit MIDI range clamp to `[0, 127]` rather than wrap —
/// the alternative (silent loss) would surprise more than it would help.
///
/// The shift is applied to the note's (possibly fractional) pitch, so any
/// microtonal offset a note already carries survives the transpose.
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
      .map((n) => n.copyWith(pitch: (n.pitch + semitones).clamp(0.0, 127.0)))
      .toList(growable: false);

  @override
  TransposeTransform copyWith({bool? active, String? label}) =>
      TransposeTransform(
        semitones: semitones,
        label: label ?? this.label,
        active: active ?? this.active,
      );

  @override
  List<TransformParam> get params => [
    IntParam(name: 'semitones', value: semitones, min: -127, max: 127),
  ];

  @override
  TransposeTransform withParam(String name, num value) => switch (name) {
    'semitones' => TransposeTransform(
      semitones: value.toInt(),
      label: label,
      active: active,
    ),
    _ => throw ArgumentError.value(name, 'name', 'not an editable parameter'),
  };
}
