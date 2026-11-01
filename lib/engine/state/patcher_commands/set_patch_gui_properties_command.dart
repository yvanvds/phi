import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Sets several **decoration** GUI properties of one node (`PatchGuiProperty`)
/// as a single undoable step — a `.kslider`'s range shifted by an octave moves
/// both its `lo` and its `hi` (issue #515), and one `Ctrl+Z` must put both
/// back.
///
/// [apply] captures every key's current value on its first run, so an
/// undo→redo cannot drift. An empty string means "unset" in both directions.
class SetPatchGuiPropertiesCommand implements ProjectCommand {
  SetPatchGuiPropertiesCommand(
    this.controller,
    this.id, {
    required this.values,
    this.label = 'set gui properties',
  });

  final PatcherController controller;

  /// The node whose decoration changes.
  final PatchNodeId id;

  /// Each GUI property key and its new value (`''` clears it).
  final Map<String, String> values;

  @override
  final String label;

  /// What [revert] restores, captured by the first [apply].
  Map<String, String>? _restore;

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    _restore ??= {
      for (final key in values.keys) key: controller.guiPropertyOf(id, key),
    };
    values.forEach((key, value) {
      controller.setGuiPropertyPrimitive(id, key, value);
    });
  }

  @override
  void revert() {
    _restore?.forEach((key, value) {
      controller.setGuiPropertyPrimitive(id, key, value);
    });
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_set_gui_properties',
    'values': values,
  };
}
