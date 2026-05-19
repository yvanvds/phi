import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Placeholder for transforms whose semantics are designed but unimplemented.
///
/// Six of the eight chips in the default chain ship as `StubTransform`s so
/// the sidebar UI populates fully while the real implementations land in
/// follow-up issues. `apply` is the identity — the pill still toggles, but
/// the piano roll doesn't change.
class StubTransform extends MidiTransform {
  const StubTransform({
    required this.kind,
    required this.label,
    this.active = true,
  });

  @override
  final MidiTransformKind kind;

  @override
  final String label;

  @override
  final bool active;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input;

  @override
  StubTransform copyWith({bool? active}) =>
      StubTransform(kind: kind, label: label, active: active ?? this.active);
}
