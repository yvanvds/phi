import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../patch_edit_gateway.dart';

/// Sets a creation parameter on one node of the patch at [patchAddress] — the
/// *param-change* gesture (design `docs/design/patcher.md` §3, §7, the
/// metadata-driven params dialog).
///
/// [apply] captures the parameter's prior value before setting the new one, so
/// [revert] restores it exactly — and if the parameter had no prior value it
/// is cleared again, so introducing a key round-trips too. The prior value is
/// captured only on the first [apply] so an undo→redo does not drift.
class ParamChangeCommand implements ProjectCommand {
  /// Sets parameter [name] of the object at [objectId] to [value] on the patch
  /// at [patchAddress].
  ParamChangeCommand(
    this.gateway,
    this.patchAddress,
    this.objectId,
    this.name,
    this.value,
  );

  /// The seam the gesture is forwarded through.
  final PatchEditGateway gateway;

  /// The `patch.` entity being edited — dirtied so save re-dumps it.
  final EntityAddress patchAddress;

  /// The handle id of the object whose parameter changes.
  final int objectId;

  /// The parameter name.
  final String name;

  /// The value to set.
  final double value;

  double? _old;
  bool _captured = false;

  @override
  String get label => 'set $name';

  @override
  Set<EntityAddress> get entitiesTouched => {patchAddress};

  @override
  void apply() {
    if (!_captured) {
      _old = gateway.paramOf(objectId, name);
      _captured = true;
    }
    gateway.setParam(objectId, name, value);
  }

  @override
  void revert() {
    final old = _old;
    if (old == null) {
      gateway.clearParam(objectId, name);
    } else {
      gateway.setParam(objectId, name, old);
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'param_change',
    'patch': patchAddress.format(),
    'id': objectId,
    'name': name,
    'value': value,
  };
}
