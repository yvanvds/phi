import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Mirrors every note's pitch around a fixed [axis]. A pitch `p` maps to
/// `2 * axis - p`, so notes above the axis fall below it by the same
/// interval and vice-versa; a note sitting exactly on the axis is unmoved.
///
/// [axis] is a fractional pitch number rather than an `int` so the mirror
/// can sit *between* two keys — inverting around 60.5 swaps C4↔D4 without
/// leaving a fixed point on a played note, which is the usual musical
/// intent. The reflected pitch is rounded to the nearest semitone and
/// clamped to `[0, 127]` (matching [TransposeTransform]'s clamp-not-wrap
/// choice) so extreme axes can't push notes out of MIDI range.
///
/// A scale-degree axis is expressed by passing that degree's pitch as
/// [axis]; the transform itself is scale-agnostic.
class InversionTransform extends MidiTransform {
  const InversionTransform({
    required this.axis,
    required this.label,
    this.active = true,
  });

  /// The mirror point, as a (possibly fractional) MIDI pitch number.
  final double axis;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.pitch;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input
      .map((n) => n.copyWith(pitch: _mirror(n.pitch)))
      .toList(growable: false);

  @override
  InversionTransform copyWith({bool? active}) => InversionTransform(
    axis: axis,
    label: label,
    active: active ?? this.active,
  );

  int _mirror(int pitch) => (2 * axis - pitch).round().clamp(0, 127);
}
