import 'dsl_note.dart';
import 'midi_transform_kind.dart';
import 'transforms/custom_transform.dart';

/// A named, live-updatable custom transform registered from the Code surface.
///
/// The [name] identifies it in the chain `+` menu and is the hot-reload key:
/// re-evaluating the block that defines it calls `CustomTransformRegistry
/// .register` again with the same name, which swaps [transform] in place on
/// this same definition object (see [updateTransform]). Because every
/// [CustomTransform] placed in a chain holds the *definition* — not the raw
/// function — those chips transparently pick up the new logic on the next
/// apply, without being removed or re-ordered. That is what lets hot-reload
/// preserve chain state (issue #38).
///
/// [kind] fixes the transform's family (and therefore its chip colour/tag) for
/// the life of the definition; only the function is hot-reloaded.
class CustomTransformDefinition {
  CustomTransformDefinition({
    required this.name,
    required this._transform,
    this.kind = MidiTransformKind.struct,
  });

  final String name;
  final MidiTransformKind kind;

  DslTransform _transform;
  int _revision = 0;

  /// The function this definition currently runs. Updated in place on
  /// hot-reload via [updateTransform].
  DslTransform get transform => _transform;

  /// Monotonic counter bumped every time [updateTransform] swaps the function.
  /// A [CustomTransform] surfaces this as its own revision so a chain that
  /// memoises its output invalidates the cache on hot-reload — the one signal
  /// that changes what `apply` produces without the chain's transform list
  /// changing.
  int get revision => _revision;

  /// Hot-reload hook: replace the function this definition runs. Called by
  /// `CustomTransformRegistry.register` when a definition of the same name is
  /// re-registered; any [CustomTransform] holding this definition then runs the
  /// new logic on its next apply.
  void updateTransform(DslTransform transform) {
    _transform = transform;
    _revision++;
  }

  /// Builds a chain-ready [CustomTransform] bound to this definition.
  CustomTransform instantiate({bool active = true}) =>
      CustomTransform(definition: this, active: active);
}
