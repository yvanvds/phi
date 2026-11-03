import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patch_node_spec.dart';
import '../patcher_controller.dart';

/// Deletes a set of selected nodes **with their cables** — the node-delete
/// gesture (design `docs/design/patcher.md` §6). [apply] captures each node's
/// full [PatchNodeSpec] and every cable touching the set, drops the cables,
/// then removes the nodes; [revert] restores every node under its original id
/// and re-wires each captured cable, so the graph returns exactly as it was.
///
/// A subpatch box is deleted with its whole contents, and an undo brings them
/// back under their own ids, box first (issue #481).
///
/// The capture refreshes on every [apply] so a redo after further edits still
/// restores the then-current state. Restoring under the same [PatchNodeId]
/// keeps any lower undo commands that named those nodes valid.
class DeletePatchNodesCommand implements ProjectCommand {
  DeletePatchNodesCommand(this.controller, Set<PatchNodeId> ids)
    : ids = Set.unmodifiable(ids);

  final PatcherController controller;
  final Set<PatchNodeId> ids;

  /// The nodes actually removed: [ids] plus, for a subpatch box, everything
  /// inside it (issue #481), containers before contents.
  List<PatchNodeId> _order = const [];
  Map<PatchNodeId, PatchNodeSpec> _specs = const {};
  List<PatchCable> _cables = const [];

  @override
  String get label => 'delete ${ids.length} node(s)';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    _order = controller.subtreeOf(ids);
    _specs = {for (final id in _order) id: controller.captureSpec(id)};
    _cables = controller.cablesTouching(_order.toSet());
    for (final cable in _cables) {
      controller.removeCablePrimitive(cable);
    }
    for (final id in _order.reversed) {
      controller.deleteNodePrimitive(id);
    }
  }

  @override
  void revert() {
    for (final id in _order) {
      controller.restoreNodePrimitive(id, _specs[id]!);
    }
    for (final cable in _cables) {
      controller.addCablePrimitive(cable);
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_delete_nodes',
    'nodes': ids.length,
  };
}
