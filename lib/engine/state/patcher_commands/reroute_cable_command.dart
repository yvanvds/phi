import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../patcher_controller.dart';

/// Moves one end of an existing cable to a different port — the detach-and-drop
/// gesture (issue #359): grab a cable near either endpoint, drag it off, and
/// let go on another port.
///
/// Deliberately **one** command rather than a delete followed by a connect: a
/// re-route is a single thing the user did, so `Ctrl+Z` puts the cable back
/// where it was in one step instead of leaving the patch briefly unwired
/// halfway through the undo.
class RerouteCableCommand implements ProjectCommand {
  RerouteCableCommand(this.controller, {required this.from, required this.to});

  final PatcherController controller;

  /// The cable as it was before the gesture.
  final PatchCable from;

  /// The cable the drop landed on.
  final PatchCable to;

  @override
  String get label => 'reroute cable';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    controller.removeCablePrimitive(from);
    controller.addCablePrimitive(to);
  }

  @override
  void revert() {
    controller.removeCablePrimitive(to);
    controller.addCablePrimitive(from);
  }

  @override
  Map<String, Object?> toJson() => const {'type': 'patch_reroute_cable'};
}
