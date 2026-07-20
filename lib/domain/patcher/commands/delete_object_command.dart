import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../patch_connection.dart';
import '../patch_edit_gateway.dart';
import '../patch_object_spec.dart';

/// Deletes one object — **with its cables** — from the patch at [patchAddress]
/// (design `docs/design/patcher.md` §3, §6).
///
/// [apply] first captures the object's [PatchObjectSpec] and every connection
/// touching it (through the [gateway]'s read surface), then removes it; the
/// gateway drops the incident cables as part of the removal. [revert] restores
/// the object under its original id and re-wires each captured connection, so a
/// delete undoes to the exact prior graph. The capture is refreshed on every
/// [apply] so a redo after further edits still restores the current state.
class DeleteObjectCommand implements ProjectCommand {
  /// Deletes the object at [objectId] from the patch at [patchAddress].
  DeleteObjectCommand(this.gateway, this.patchAddress, this.objectId);

  /// The seam the gesture is forwarded through.
  final PatchEditGateway gateway;

  /// The `patch.` entity being edited — dirtied so save re-dumps it.
  final EntityAddress patchAddress;

  /// The handle id of the object to delete.
  final int objectId;

  PatchObjectSpec? _spec;
  List<PatchConnection> _cables = const [];

  @override
  String get label => 'delete object $objectId';

  @override
  Set<EntityAddress> get entitiesTouched => {patchAddress};

  @override
  void apply() {
    _spec = gateway.describe(objectId);
    _cables = gateway.connectionsOf(objectId);
    gateway.removeObject(objectId);
  }

  @override
  void revert() {
    gateway.restoreObject(objectId, _spec!);
    for (final cable in _cables) {
      gateway.connect(cable);
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'delete_object',
    'patch': patchAddress.format(),
    'id': objectId,
  };
}
