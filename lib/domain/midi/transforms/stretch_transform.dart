import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Scales the clip along the time axis: every note's start and duration are
/// multiplied by [factor]. `2.0` halves the tempo feel (the phrase takes twice
/// as long), `0.5` doubles it. Pitch, velocity, and channel are untouched — a
/// stretch only rescales *when* notes play, not *what* they are.
///
/// [factor] is expected to be positive. A non-positive factor would fold the
/// clip onto (or behind) the origin, so it's treated as the identity rather
/// than emitting zero-length or negatively-placed notes.
class StretchTransform extends MidiTransform {
  const StretchTransform({
    required this.factor,
    required this.label,
    this.active = true,
  });

  /// Time multiplier. `< 1` compresses, `> 1` expands.
  final double factor;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.time;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    if (factor <= 0) return input;
    return input
        .map(
          (n) => n.copyWith(
            start: n.start * factor,
            duration: n.duration * factor,
          ),
        )
        .toList(growable: false);
  }

  @override
  StretchTransform copyWith({bool? active, String? label}) => StretchTransform(
    factor: factor,
    label: label ?? this.label,
    active: active ?? this.active,
  );
}
