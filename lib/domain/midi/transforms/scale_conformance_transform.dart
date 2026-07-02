import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../music_scale.dart';
import '../scale_tuning.dart';

/// Snaps each note's pitch to the nearest degree of a [ScaleTuning], crossing
/// the tuning's period (an octave, by default) freely so a note never moves
/// further than half a period.
///
/// The tuning is expressed in **cents**, not the 12-semitone integer grid, so
/// this transform handles microtonal targets: just intonation, arbitrary cents
/// tables, non-octave scales (issue #36). The common 12-TET diatonic case is
/// [ScaleConformanceTransform.diatonic], which builds the tuning from a
/// [MusicScale] and reproduces the old integer behaviour exactly.
///
/// Both the incoming pitch and the [tonic] may be fractional, so a microtonal
/// clip snaps to a microtonal scale without ever rounding to a semitone. Ties
/// (a pitch equidistant from two degrees, e.g. C♯ in C-dorian between C and D)
/// resolve **upward** — Phi prefers the brighter interpretation by default.
class ScaleConformanceTransform extends MidiTransform {
  ScaleConformanceTransform({
    required this.tuning,
    required this.tonic,
    required this.label,
    this.active = true,
  });

  /// Convenience constructor for a plain 12-TET diatonic mode.
  ScaleConformanceTransform.diatonic({
    required MusicScale scale,
    required double tonic,
    required String label,
    bool active = true,
  }) : this(
         tuning: ScaleTuning.diatonic(scale),
         tonic: tonic,
         label: label,
         active: active,
       );

  final ScaleTuning tuning;
  final double tonic;

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
        tuning: tuning,
        tonic: tonic,
        label: label,
        active: active ?? this.active,
      );

  /// Nearest scale degree to [pitch], measured in cents from [tonic] and
  /// reduced into one period, then re-expanded to the note's own octave.
  double _snap(double pitch) {
    final period = tuning.periodCents;
    if (period <= 0 || tuning.degreesCents.isEmpty) return pitch;

    final centsFromTonic = (pitch - tonic) * 100.0;
    final pc = centsFromTonic % period; // Dart % is non-negative here.

    var bestDelta = double.negativeInfinity; // signed cents to add.
    var bestDist = double.infinity;
    for (final degree in tuning.degreesCents) {
      // Consider the neighbouring periods so a snap can cross the boundary.
      for (final candidate in [degree - period, degree, degree + period]) {
        final delta = candidate - pc;
        final dist = delta.abs();
        // Tie-break upward: on an equidistant pitch, prefer the larger delta.
        if (dist < bestDist - _epsilon ||
            (dist <= bestDist + _epsilon && delta > bestDelta)) {
          bestDist = dist;
          bestDelta = delta;
        }
      }
    }

    final snappedCents = centsFromTonic + bestDelta;
    return (tonic + snappedCents / 100.0).clamp(0.0, 127.0);
  }

  static const double _epsilon = 1e-6;
}
