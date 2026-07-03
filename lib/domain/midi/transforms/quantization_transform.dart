import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Pulls each note's start toward the nearest point on a beat [grid], with
/// [gravity] controlling how far. `gravity == 0` is the identity (snap off);
/// `gravity == 1` snaps hard onto the grid; values in between move the note
/// that fraction of the way, so `0.6` closes 60% of the distance to the
/// nearest grid line — a musical "tighten, don't robotise" feel.
///
/// Only the start is quantised; [MidiNote.duration] is left alone, so a note
/// keeps its length as it slides onto the grid (quantising note-offs too is a
/// separate, rarely-wanted behaviour). [grid] is a beat interval — `0.25` is a
/// sixteenth at 4/4. A non-positive grid is treated as "no grid" and the
/// transform passes notes through unchanged rather than dividing by zero.
class QuantizationTransform extends MidiTransform {
  const QuantizationTransform({
    required this.gravity,
    required this.label,
    this.grid = 0.25,
    this.active = true,
  });

  /// How strongly notes are pulled to the grid, clamped to `[0, 1]`.
  final double gravity;

  /// Grid spacing in beats. A sixteenth at 4/4 is `0.25`.
  final double grid;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.time;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    final g = gravity.clamp(0.0, 1.0);
    if (grid <= 0 || g == 0) return input;
    return input
        .map((n) => n.copyWith(start: _snap(n.start, g)))
        .toList(growable: false);
  }

  @override
  QuantizationTransform copyWith({bool? active, String? label}) =>
      QuantizationTransform(
        gravity: gravity,
        label: label ?? this.label,
        grid: grid,
        active: active ?? this.active,
      );

  double _snap(double start, double g) {
    final target = (start / grid).round() * grid;
    return start + g * (target - start);
  }
}
