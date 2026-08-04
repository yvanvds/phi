import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Reconfigures one node's creation parameters in a single undoable step — the
/// params-dialog gesture (design `docs/design/patcher.md` §7). The dialog joins
/// its per-parameter fields into a whitespace-separated argument string and
/// authors this command through [PatcherController.applyParams].
///
/// [apply] captures the node's prior argument string before setting the new one
/// (once, on the first apply, so an undo→redo does not drift); [revert] restores
/// it — so a param edit round-trips exactly under Ctrl+Z/Y.
///
/// Arguments can also change how many ports the object *has*, and a shrink
/// leaves cables with nowhere to land. Those are dropped by the controller and
/// captured here, so [revert] — which brings the ports back with the old
/// arguments — can wire them again and the whole edit undoes without costing
/// the patch a connection (issue #356).
class SetPatchParamsCommand implements ProjectCommand {
  SetPatchParamsCommand(this.controller, this.id, this.args);

  final PatcherController controller;

  /// The node whose creation arguments change.
  final PatchNodeId id;

  /// The new whitespace-joined argument string.
  final String args;

  String? _old;
  bool _captured = false;

  /// Cables the last [apply] had to drop because the new arguments removed the
  /// port they hung off. Empty for the overwhelmingly common fixed-arity case.
  List<PatchCable> _dropped = const [];

  @override
  String get label => 'set params';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    if (!_captured) {
      _old = controller.argsOf(id);
      _captured = true;
    }
    _dropped = controller.setNodeParams(id, args);
  }

  @override
  void revert() {
    // Restoring the old arguments restores the old ports, so the cables the
    // apply had to drop have somewhere to land again.
    controller.setNodeParams(id, _old ?? '');
    for (final cable in _dropped) {
      controller.addCablePrimitive(cable);
    }
    _dropped = const [];
  }

  @override
  Map<String, Object?> toJson() => {'type': 'patch_set_params', 'args': args};
}
