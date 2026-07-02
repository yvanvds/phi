import 'dart:math';

import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Adds small random jitter to every note's start time and velocity to shake
/// off the mechanical grid. Each note's start is nudged by a uniform amount in
/// `[-timeRange, +timeRange]` beats and its velocity by a uniform amount in
/// `[-velocityRange, +velocityRange]`.
///
/// The jitter is **seedable and reproducible**: [apply] builds a fresh
/// `Random(seed)` each call and walks the notes in order, so the same [seed]
/// over the same input always yields the same output — the transform stays
/// pure, which the chain relies on. Change the seed to audition a different
/// "performance" of the same range.
///
/// Nudged starts are clamped to `>= 0` (a note can't precede the clip origin)
/// and velocities to `[0, 1]` (the normalised range [MidiNote] carries).
class HumanizationTransform extends MidiTransform {
  const HumanizationTransform({
    required this.label,
    this.timeRange = 0.02,
    this.velocityRange = 0.1,
    this.seed = 0,
    this.active = true,
  });

  /// Maximum start-time nudge in beats, applied symmetrically (±).
  final double timeRange;

  /// Maximum velocity nudge in normalised units, applied symmetrically (±).
  final double velocityRange;

  /// Seed for the pseudo-random jitter. Same seed + input ⇒ same output.
  final int seed;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.time;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    final rng = Random(seed);
    return input
        .map((n) {
          final start = (n.start + _jitter(rng, timeRange)).clamp(
            0.0,
            double.infinity,
          );
          final velocity = (n.velocity + _jitter(rng, velocityRange)).clamp(
            0.0,
            1.0,
          );
          return n.copyWith(start: start, velocity: velocity);
        })
        .toList(growable: false);
  }

  @override
  HumanizationTransform copyWith({bool? active}) => HumanizationTransform(
    label: label,
    timeRange: timeRange,
    velocityRange: velocityRange,
    seed: seed,
    active: active ?? this.active,
  );

  /// Uniform draw in `[-range, +range]`. Both draws happen unconditionally and
  /// in a fixed order so the RNG stream stays aligned across runs.
  double _jitter(Random rng, double range) =>
      (rng.nextDouble() * 2 - 1) * range;
}
