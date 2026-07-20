import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../patch_edit_gateway.dart';
import '../patch_point.dart';

/// Moves one node to [to] on the patch at [patchAddress] — the *move-node*
/// gesture (design `docs/design/patcher.md` §3, §6). Positions ride in the
/// engine GUI properties, so a move dirties the patch like any other edit.
///
/// [apply] captures the node's position before moving so [revert] restores it
/// exactly. The origin is captured only on the first [apply], so an
/// undo→redo restores the original position rather than drifting.
class MoveNodeCommand implements ProjectCommand {
  /// Moves the object at [objectId] to [to] on the patch at [patchAddress].
  MoveNodeCommand(this.gateway, this.patchAddress, this.objectId, this.to);

  /// The seam the gesture is forwarded through.
  final PatchEditGateway gateway;

  /// The `patch.` entity being edited — dirtied so save re-dumps it.
  final EntityAddress patchAddress;

  /// The handle id of the object to move.
  final int objectId;

  /// The destination position.
  final PatchPoint to;

  PatchPoint? _from;

  @override
  String get label => 'move node $objectId';

  @override
  Set<EntityAddress> get entitiesTouched => {patchAddress};

  @override
  void apply() {
    _from ??= gateway.positionOf(objectId);
    gateway.moveObject(objectId, to);
  }

  @override
  void revert() => gateway.moveObject(objectId, _from!);

  @override
  Map<String, Object?> toJson() => {
    'type': 'move_node',
    'patch': patchAddress.format(),
    'id': objectId,
    'to': to.toJson(),
  };
}
