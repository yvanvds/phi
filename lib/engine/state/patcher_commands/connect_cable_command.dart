import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Wires one typed cable into the graph — the connect gesture (design
/// `docs/design/patcher.md` §6). [apply] adds the cable (native + Dart mirror);
/// [revert] removes it.
class ConnectCableCommand implements ProjectCommand {
  ConnectCableCommand(this.controller, this.cable);

  final PatcherController controller;
  final PatchCable cable;

  @override
  String get label => 'connect';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() => controller.addCablePrimitive(cable);

  @override
  void revert() => controller.removeCablePrimitive(cable);

  @override
  Map<String, Object?> toJson() => const {'type': 'patch_connect'};
}
