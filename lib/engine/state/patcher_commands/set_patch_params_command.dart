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
class SetPatchParamsCommand implements ProjectCommand {
  SetPatchParamsCommand(this.controller, this.id, this.args);

  final PatcherController controller;

  /// The node whose creation arguments change.
  final PatchNodeId id;

  /// The new whitespace-joined argument string.
  final String args;

  String? _old;
  bool _captured = false;

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
    controller.setNodeParams(id, args);
  }

  @override
  void revert() => controller.setNodeParams(id, _old ?? '');

  @override
  Map<String, Object?> toJson() => {'type': 'patch_set_params', 'args': args};
}
