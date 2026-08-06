import '../custom_transform_definition.dart';
import '../dsl_note.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// A [MidiTransform] whose behaviour is authored by the performer on the Code
/// surface and registered via `CustomTransformRegistry` (issue #38).
///
/// It holds the [definition] rather than a raw function so hot-reload works:
/// when the performer re-evaluates their block, the definition's function is
/// swapped in place and this chip — still at its position in the chain, still
/// active/inactive as the performer left it — runs the new logic on its next
/// [apply].
///
/// [apply] bridges the two note worlds: domain [MidiNote]s in, [DslNote]s to
/// the performer's function, domain [MidiNote]s back out. Like every transform
/// it is expected to be pure for a given definition revision so the chain
/// stays memoisable; the function itself is trusted to be pure (a throwing or
/// impure live-coded function surfaces upstream, on the Code surface).
class CustomTransform extends MidiTransform {
  const CustomTransform({
    required this.definition,
    this.active = true,
    this._label,
  });

  /// The live, hot-reloadable unit this chip runs. Shared with the registry and
  /// with any other chip built from the same definition.
  final CustomTransformDefinition definition;

  /// Per-chip rename override. `null` falls back to the definition name, so a
  /// freshly-added chip reads as its registered name until the performer
  /// renames it; renaming one chip never touches the definition or its twins.
  final String? _label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => definition.kind;

  @override
  String get label => _label ?? definition.name;

  @override
  int get revision => definition.revision;

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    final dsl = input.map(DslNote.fromNote).toList(growable: false);
    final result = definition.transform(dsl);
    return result.map((note) => note.toNote()).toList(growable: false);
  }

  @override
  CustomTransform copyWith({bool? active, String? label}) => CustomTransform(
    definition: definition,
    active: active ?? this.active,
    label: label ?? _label,
  );
}
