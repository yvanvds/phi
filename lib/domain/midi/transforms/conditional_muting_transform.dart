import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Gates a note through or drops it. The signature is deliberately minimal —
/// mirrors the `VelocityCurve` seam in `velocity_to_parameter_transform.dart`
/// — so a state-machine read, a scene-volume check, or a live-coded variable
/// can stand behind it later without this transform changing.
typedef NotePredicate = bool Function(MidiNote note);

/// Drops notes that fail [predicate], keeping everything else in place.
///
/// This is the boolean seed for what the vision calls conditional muting:
/// gating notes by state-machine state, scene volume, or a code variable.
/// None of that plumbing exists yet, so [predicate] starts as a plain Dart
/// callback the caller supplies directly — same as `VelocityCurve`. Like
/// every transform, it must be pure (same note, same verdict) so the chain
/// stays memoisable.
class ConditionalMutingTransform extends MidiTransform {
  const ConditionalMutingTransform({
    required this.predicate,
    required this.label,
    this.active = true,
  });

  /// Notes for which this returns `false` are dropped.
  final NotePredicate predicate;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.struct;

  @override
  List<MidiNote> apply(List<MidiNote> input) =>
      input.where(predicate).toList(growable: false);

  @override
  ConditionalMutingTransform copyWith({bool? active}) =>
      ConditionalMutingTransform(
        predicate: predicate,
        label: label,
        active: active ?? this.active,
      );
}
