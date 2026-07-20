import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Removes a selected cable — the cable-delete gesture (design
/// `docs/design/patcher.md` §6, "click a cable to select, Delete removes it").
/// [apply] drops the cable; [revert] re-wires it exactly.
class DeleteCableCommand implements ProjectCommand {
  DeleteCableCommand(this.controller, this.cable);

  final PatcherController controller;
  final PatchCable cable;

  @override
  String get label => 'delete cable';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() => controller.removeCablePrimitive(cable);

  @override
  void revert() => controller.addCablePrimitive(cable);

  @override
  Map<String, Object?> toJson() => const {'type': 'patch_delete_cable'};
}
