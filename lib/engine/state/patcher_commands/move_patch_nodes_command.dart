import 'dart:ui';

import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Moves one or more canvas nodes to new positions in a single undoable step —
/// the body-drag gesture (design `docs/design/patcher.md` §6). A drag previews
/// live on the [PatchNode]s and commits this one command on release.
///
/// [apply] places every node at its captured destination (and persists to the
/// engine's GUI properties); [revert] restores each origin, so one undo returns
/// the whole moved set exactly where it started. Both maps are keyed by the
/// stable [PatchNodeId], so a redo after unrelated edits still lands right.
class MovePatchNodesCommand implements ProjectCommand {
  MovePatchNodesCommand(
    this.controller, {
    required this.from,
    required this.to,
  });

  final PatcherController controller;

  /// Origin position per node — where [revert] restores each.
  final Map<PatchNodeId, Offset> from;

  /// Destination position per node — where [apply] places each.
  final Map<PatchNodeId, Offset> to;

  @override
  String get label => 'move ${to.length} node(s)';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    to.forEach(controller.placeNode);
  }

  @override
  void revert() {
    from.forEach(controller.placeNode);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_move_nodes',
    'nodes': to.length,
  };
}
