import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Sets one **decoration** GUI property of a node (`PatchGuiProperty`) as a
/// single undoable step — the note's right-edge resize writes its `w` this way
/// (issue #488), and any later decoration (a note colour) can reuse it as is.
///
/// [previous] is the value the gesture started from when the caller already
/// knows it — a live resize has been writing the property all along, so by the
/// time it is journaled the engine holds the *new* value. Without one, [apply]
/// captures the current value on its first run, so an undo→redo cannot drift.
/// An empty string means "unset" in both directions.
class SetPatchGuiPropertyCommand implements ProjectCommand {
  SetPatchGuiPropertyCommand(
    this.controller,
    this.id, {
    required this.key,
    required this.value,
    this.previous,
    this.label = 'set gui property',
  });

  final PatcherController controller;

  /// The node whose decoration changes.
  final PatchNodeId id;

  /// The GUI property key.
  final String key;

  /// The new value (`''` clears it).
  final String value;

  /// The value to restore on undo, when the caller knows it up front.
  final String? previous;

  @override
  final String label;

  /// What [revert] restores — [previous], or the value [apply] first found.
  String? _restore;

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    _restore ??= previous ?? controller.guiPropertyOf(id, key);
    controller.setGuiPropertyPrimitive(id, key, value);
  }

  @override
  void revert() => controller.setGuiPropertyPrimitive(id, key, _restore ?? '');

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_set_gui_property',
    'key': key,
    'value': value,
  };
}
