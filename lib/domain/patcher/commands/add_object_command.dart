import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../patch_edit_gateway.dart';
import '../patch_object_spec.dart';

/// Adds one object to the patch at [patchAddress] — the *add-object* gesture
/// (design `docs/design/patcher.md` §3).
///
/// [apply] forwards a create through the [gateway] and remembers the handle id
/// it was assigned; [revert] removes that object again. A redo (apply after a
/// revert) recreates it under the *same* id via
/// [PatchEditGateway.restoreObject], so any cable or later gesture that named
/// the object stays valid across an undo/redo cycle.
class AddObjectCommand implements ProjectCommand {
  /// Adds [spec] to the patch at [patchAddress] through [gateway].
  AddObjectCommand(this.gateway, this.patchAddress, this.spec);

  /// The seam the gesture is forwarded through.
  final PatchEditGateway gateway;

  /// The `patch.` entity being edited — dirtied so save re-dumps it.
  final EntityAddress patchAddress;

  /// What to create.
  final PatchObjectSpec spec;

  int? _id;

  /// The handle id assigned on the first [apply], or `null` before then.
  int? get objectId => _id;

  @override
  String get label => 'add ${spec.type}';

  @override
  Set<EntityAddress> get entitiesTouched => {patchAddress};

  @override
  void apply() {
    final id = _id;
    if (id == null) {
      _id = gateway.createObject(spec);
    } else {
      gateway.restoreObject(id, spec);
    }
  }

  @override
  void revert() => gateway.removeObject(_id!);

  @override
  Map<String, Object?> toJson() => {
    'type': 'add_object',
    'patch': patchAddress.format(),
    'spec': spec.toJson(),
    if (_id != null) 'id': _id,
  };
}
