import 'dart:math';

import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../transform_param.dart';

/// Thins and stutters a phrase probabilistically. For each incoming note two
/// independent draws are made, in a fixed order:
///
/// 1. **Skip** — with probability [skipProbability] the note is dropped
///    entirely. A skipped note is not considered for repeat.
/// 2. **Repeat** — otherwise, with probability [repeatProbability], the note is
///    followed by [repeatCount] echoes. Each echo `i` (1..N) is a copy shifted
///    to `start + i * duration`, so a note rolls into a stutter of back-to-back
///    copies of the same pitch, length, and velocity.
///
/// The draws are **seedable and reproducible**: [apply] builds a fresh
/// `Random(seed)` per call and walks notes in order, so the same [seed] over
/// the same input always produces the same result — keeping the transform pure.
/// Both draws happen for every surviving note (the skip draw for every note),
/// so the RNG stream stays aligned regardless of outcomes.
///
/// Echoes may land past the clip's nominal length; that's left to the host, the
/// same as any other transform that moves notes in time.
class ProbabilisticSkipRepeatTransform extends MidiTransform {
  const ProbabilisticSkipRepeatTransform({
    required this.label,
    this.skipProbability = 0.0,
    this.repeatProbability = 0.0,
    this.repeatCount = 1,
    this.seed = 0,
    this.active = true,
  });

  /// Chance in `[0, 1]` that a note is dropped.
  final double skipProbability;

  /// Chance in `[0, 1]` that a surviving note is echoed.
  final double repeatProbability;

  /// Number of echoes appended when a repeat fires (`N`). Clamped to `>= 1`.
  final int repeatCount;

  /// Seed for the pseudo-random draws. Same seed + input ⇒ same output.
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
    final echoes = repeatCount < 1 ? 1 : repeatCount;
    final out = <MidiNote>[];
    for (final n in input) {
      final skipRoll = rng.nextDouble();
      final repeatRoll = rng.nextDouble();
      if (skipRoll < skipProbability) continue;
      out.add(n);
      if (repeatRoll < repeatProbability) {
        for (var i = 1; i <= echoes; i++) {
          out.add(n.copyWith(start: n.start + i * n.duration));
        }
      }
    }
    return out;
  }

  @override
  ProbabilisticSkipRepeatTransform copyWith({bool? active, String? label}) =>
      ProbabilisticSkipRepeatTransform(
        label: label ?? this.label,
        skipProbability: skipProbability,
        repeatProbability: repeatProbability,
        repeatCount: repeatCount,
        seed: seed,
        active: active ?? this.active,
      );

  @override
  List<TransformParam> get params => [
    DoubleParam(name: 'skip', value: skipProbability, min: 0, max: 1),
    DoubleParam(name: 'repeat', value: repeatProbability, min: 0, max: 1),
    IntParam(name: 'echoes', value: repeatCount, min: 1),
    IntParam(name: 'seed', value: seed, min: 0),
  ];

  @override
  ProbabilisticSkipRepeatTransform withParam(String name, num value) =>
      switch (name) {
        'skip' => _with(skipProbability: value.toDouble()),
        'repeat' => _with(repeatProbability: value.toDouble()),
        'echoes' => _with(repeatCount: value.toInt()),
        'seed' => _with(seed: value.toInt()),
        _ => throw ArgumentError.value(
          name,
          'name',
          'not an editable parameter',
        ),
      };

  ProbabilisticSkipRepeatTransform _with({
    double? skipProbability,
    double? repeatProbability,
    int? repeatCount,
    int? seed,
  }) => ProbabilisticSkipRepeatTransform(
    label: label,
    skipProbability: skipProbability ?? this.skipProbability,
    repeatProbability: repeatProbability ?? this.repeatProbability,
    repeatCount: repeatCount ?? this.repeatCount,
    seed: seed ?? this.seed,
    active: active,
  );
}
