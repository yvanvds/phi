import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../music_scale.dart';

/// Snaps each note's pitch to the nearest pitch in the configured scale,
/// crossing octaves freely so a note never moves further than 6 semitones.
///
/// Ties (a pitch equidistant from two scale degrees, e.g. C# in C-dorian
/// between C and D) resolve **upward** — Phi prefers the brighter
/// interpretation by default.
class ScaleConformanceTransform extends MidiTransform {
  const ScaleConformanceTransform({
    required this.scale,
    required this.tonic,
    required this.label,
    this.active = true,
  });

  final MusicScale scale;
  final int tonic;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.pitch;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input
      .map((n) => n.copyWith(pitch: _snap(n.pitch)))
      .toList(growable: false);

  @override
  ScaleConformanceTransform copyWith({bool? active}) =>
      ScaleConformanceTransform(
        scale: scale,
        tonic: tonic,
        label: label,
        active: active ?? this.active,
      );

  int _snap(int pitch) {
    final pc = ((pitch - tonic) % 12 + 12) % 12;
    var bestDelta = 0;
    var bestDist = 1 << 30;
    for (final i in scale.intervals) {
      for (final candidate in [i - 12, i, i + 12]) {
        final delta = candidate - pc;
        final dist = delta.abs();
        if (dist < bestDist || (dist == bestDist && delta > bestDelta)) {
          bestDist = dist;
          bestDelta = delta;
        }
      }
    }
    return (pitch + bestDelta).clamp(0, 127);
  }
}
