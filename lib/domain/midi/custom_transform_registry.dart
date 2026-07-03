import 'package:flutter/foundation.dart';

import 'custom_transform_definition.dart';
import 'dsl_note.dart';
import 'midi_transform_kind.dart';

/// Live catalogue of performer-authored [CustomTransformDefinition]s.
///
/// This is the seam the Code surface's DSL writes into (issue #38): a
/// live-coded `def my_transform(notes): ...` bridges to [register], which
/// either adds a new definition or — when one of the same name already
/// exists — hot-reloads it in place by swapping the function on the existing
/// definition (see [CustomTransformDefinition]). The MIDI surface's chain `+`
/// menu reads [definitions] to offer them.
///
/// The real Python kernel that calls [register] is still open — issue #38
/// depends on #9's evaluator evolving past `NoOpCodeEvaluator` — so today the
/// registration handshake is exercised through `FakeCodeEvaluator` in tests.
/// A registry lives above the MIDI and Code surfaces so a transform authored
/// in one becomes available in the other.
class CustomTransformRegistry extends ChangeNotifier {
  final Map<String, CustomTransformDefinition> _byName = {};

  /// Registered definitions in insertion order (a re-registration keeps its
  /// original slot rather than jumping to the end).
  List<CustomTransformDefinition> get definitions =>
      List.unmodifiable(_byName.values);

  /// The definition registered under [name], or `null` if none.
  CustomTransformDefinition? operator [](String name) => _byName[name];

  /// Whether a definition named [name] is registered.
  bool contains(String name) => _byName.containsKey(name);

  /// Registers [transform] under [name], or hot-reloads an existing definition
  /// of that name by swapping its function in place. Returns the new or updated
  /// definition. Notifies listeners either way so the `+` menu and any bound
  /// chain rebuild.
  ///
  /// [kind] is honoured only when creating a new definition; on hot-reload the
  /// existing family is preserved (only the function reloads).
  CustomTransformDefinition register({
    required String name,
    required DslTransform transform,
    MidiTransformKind kind = MidiTransformKind.struct,
  }) {
    final existing = _byName[name];
    if (existing != null) {
      existing.updateTransform(transform);
      notifyListeners();
      return existing;
    }
    final created = CustomTransformDefinition(
      name: name,
      transform: transform,
      kind: kind,
    );
    _byName[name] = created;
    notifyListeners();
    return created;
  }

  /// Removes the definition named [name], if present, and notifies. Any
  /// [CustomTransform] chips already placed in a chain keep working — they hold
  /// the definition object directly — but the transform is no longer offered in
  /// the `+` menu.
  void unregister(String name) {
    if (_byName.remove(name) != null) notifyListeners();
  }
}
