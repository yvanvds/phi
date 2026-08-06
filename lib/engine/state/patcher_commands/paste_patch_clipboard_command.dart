import 'dart:ui';

import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/patcher/patch_port.dart';
import '../../../domain/patcher/patch_port_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patch_clipboard_data.dart';
import '../patcher_controller.dart';

/// Pastes a copied fragment — the `Ctrl+V` gesture (issue #435). Every node in
/// [data] is recreated [offset] from where it was copied; every copied cable is
/// recreated between the new nodes. The pasted set becomes the selection, ready
/// to drag into place.
///
/// The same shape as `DuplicatePatchSelectionCommand`, but fed from the
/// clipboard's captured specs rather than live node ids: the copied objects may
/// be long deleted — or belong to a different patch — and the paste must not
/// care. [apply] mints fresh nodes (new ids) and records them so [revert] drops
/// exactly what it added; a redo re-runs the creation from the same immutable
/// [data], so repeated undo/redo stays consistent.
class PastePatchClipboardCommand implements ProjectCommand {
  PastePatchClipboardCommand(
    this.controller, {
    required this.data,
    required this.offset,
  });

  final PatcherController controller;
  final PatchClipboardData data;
  final Offset offset;

  final List<PatchNodeId> _created = [];
  final List<PatchCable> _createdCables = [];

  @override
  String get label => 'paste ${data.nodes.length} node(s)';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    _created.clear();
    _createdCables.clear();
    for (final spec in data.nodes) {
      _created.add(controller.createNodePrimitive(spec.offsetBy(offset)));
    }
    for (final cable in data.cables) {
      final copy = PatchCable(
        source: PatchPortId(
          nodeId: _created[cable.sourceNode],
          side: PatchPortSide.output,
          index: cable.sourceOutlet,
        ),
        target: PatchPortId(
          nodeId: _created[cable.targetNode],
          side: PatchPortSide.input,
          index: cable.targetInlet,
        ),
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

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_paste',
    'nodes': data.nodes.length,
  };
}
