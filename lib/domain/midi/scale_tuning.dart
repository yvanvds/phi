import 'music_scale.dart';

/// A repeating pitch scale expressed as **cents offsets from a tonic**.
///
/// [degreesCents] lists each scale degree as cents above the tonic, sorted
/// ascending, starting at `0` and all strictly below [periodCents]. The scale
/// repeats every [periodCents] (`1200` = one octave). Describing a scale in
/// cents — rather than the 12-semitone integer grid [MusicScale] uses — lets
/// Phi snap to tunings the equal-tempered grid can't name: just intonation,
/// arbitrary cents tables, or non-octave scales (Bohlen–Pierce). See issue #36.
///
/// A plain 12-TET diatonic mode is the special case where every degree lands
/// on a multiple of 100 cents — [ScaleTuning.diatonic] builds exactly that.
class ScaleTuning {
  const ScaleTuning({required this.degreesCents, this.periodCents = 1200.0});

  /// The 12-TET reading of a diatonic [MusicScale]: each semitone interval
  /// becomes `interval × 100` cents, octave-periodic. This reproduces the old
  /// integer scale-conformance behaviour bit-for-bit.
  factory ScaleTuning.diatonic(MusicScale scale) => ScaleTuning(
    degreesCents: scale.intervals.map((i) => i * 100.0).toList(growable: false),
  );

  /// Five-limit just-intonation major scale — the classic pure-ratio scale
  /// (1/1, 9/8, 5/4, 4/3, 3/2, 5/3, 15/8). Its thirds and sixths sit a syntonic
  /// comma off the tempered grid, so snapping to it audibly "purifies" chords.
  static const ScaleTuning justMajor = ScaleTuning(
    degreesCents: [0.0, 203.91, 386.31, 498.04, 701.96, 884.36, 1088.27],
  );

  /// Five-limit just-intonation natural minor (1/1, 9/8, 6/5, 4/3, 3/2, 8/5,
  /// 9/5).
  static const ScaleTuning justMinor = ScaleTuning(
    degreesCents: [0.0, 203.91, 315.64, 498.04, 701.96, 813.69, 1017.60],
  );

  /// Cents above the tonic for each scale degree. Sorted ascending, first
  /// entry `0`, every entry `< periodCents`.
  final List<double> degreesCents;

  /// The interval after which the scale repeats, in cents. `1200` = one octave.
  final double periodCents;
}
