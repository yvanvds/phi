import 'dart:ui';

import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/patcher/patch_port_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Duplicates a selection — the `Ctrl+D` gesture (design
/// `docs/design/patcher.md` §6, "objects + intra-selection cables, offset a
/// grid step"). Each source node is recreated one grid step down-right; every
/// cable whose *both* endpoints are in the selection is recreated between the
/// copies. The duplicates become the new selection.
///
/// [apply] mints fresh nodes (new ids) and records them so [revert] can drop
/// exactly what it added. A redo re-runs the creation from the still-captured
/// source specs, so repeated undo/redo stays consistent.
class DuplicatePatchSelectionCommand implements ProjectCommand {
  DuplicatePatchSelectionCommand(
    this.controller, {
    required this.sourceIds,
    required this.offset,
  });

  final PatcherController controller;
  final Set<PatchNodeId> sourceIds;
  final Offset offset;

  final List<PatchNodeId> _created = [];
  final List<PatchCable> _createdCables = [];

  @override
  String get label => 'duplicate ${sourceIds.length} node(s)';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    _created.clear();
    _createdCables.clear();
    final idMap = <PatchNodeId, PatchNodeId>{};
    for (final id in sourceIds) {
      final spec = controller.captureSpec(id).offsetBy(offset);
      final newId = controller.createNodePrimitive(spec);
      idMap[id] = newId;
      _created.add(newId);
    }
    for (final cable in controller.cablesWithin(sourceIds)) {
      final copy = PatchCable(
        source: _remap(cable.source, idMap),
        target: _remap(cable.target, idMap),
        kind: cable.kind,
      );
      controller.addCablePrimitive(copy);
      _createdCables.add(copy);
    }
    controller.selectNodes(_created.toSet());
  }

  @override
  void revert() {
    for (final cable in _createdCables) {
      controller.removeCablePrimitive(cable);
    }
    for (final id in _created) {
      controller.deleteNodePrimitive(id);
    }
    _created.clear();
    _createdCables.clear();
  }

  static PatchPortId _remap(
    PatchPortId port,
    Map<PatchNodeId, PatchNodeId> m,
  ) => PatchPortId(nodeId: m[port.nodeId]!, side: port.side, index: port.index);

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_duplicate',
    'nodes': sourceIds.length,
  };
}
