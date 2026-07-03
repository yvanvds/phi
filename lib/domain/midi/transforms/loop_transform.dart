import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Tiles the incoming notes end-to-end across a loop window.
///
/// [loopLengthBeats] is the length of one repeat (e.g. 4 bars at 4/4 is
/// `16`). [phaseOffset] shifts every note — including the first iteration —
/// before tiling, so a loop can start mid-phrase.
///
/// How many times the loop repeats is picked by whichever of the two knobs
/// is set: [repeatCount] repeats a fixed number of times ("N bars"), or
/// [untilBeat] fills the loop until it reaches a target length ("until clip
/// end"), dropping any tail notes that would start at or past it. If both are
/// null the loop plays once — the identity. [untilBeat] takes priority when
/// both are set, since "fill to here" is the more common host-driven case.
///
/// A non-positive [loopLengthBeats] is treated as "no loop" and the input
/// passes through unchanged rather than tiling infinitely or dividing by zero.
class LoopTransform extends MidiTransform {
  const LoopTransform({
    required this.loopLengthBeats,
    required this.label,
    this.repeatCount,
    this.untilBeat,
    this.phaseOffset = 0.0,
    this.active = true,
  });

  /// Length of one loop iteration, in beats.
  final double loopLengthBeats;

  /// Fixed number of repeats. Values below `1` are clamped to `1`.
  final int? repeatCount;

  /// Target length in beats to fill the loop up to; overrides [repeatCount].
  final double? untilBeat;

  /// Beats to shift every note by before tiling.
  final double phaseOffset;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.struct;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    if (loopLengthBeats <= 0 || input.isEmpty) return input;

    final offset = phaseOffset == 0
        ? input
        : input
              .map((n) => n.copyWith(start: n.start + phaseOffset))
              .toList(growable: false);

    final iterations = untilBeat != null
        ? (untilBeat! / loopLengthBeats).ceil()
        : (repeatCount ?? 1);
    final count = iterations < 1 ? 1 : iterations;

    final out = <MidiNote>[];
    for (var i = 0; i < count; i++) {
      final shift = i * loopLengthBeats;
      for (final n in offset) {
        final shifted = n.copyWith(start: n.start + shift);
        if (untilBeat != null && shifted.start >= untilBeat!) continue;
        out.add(shifted);
      }
    }
    return out;
  }

  @override
  LoopTransform copyWith({bool? active, String? label}) => LoopTransform(
    loopLengthBeats: loopLengthBeats,
    label: label ?? this.label,
    repeatCount: repeatCount,
    untilBeat: untilBeat,
    phaseOffset: phaseOffset,
    active: active ?? this.active,
  );
}
