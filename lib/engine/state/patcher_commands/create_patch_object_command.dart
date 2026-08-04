import 'dart:ui';

import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../../bridge/patch_object_descriptor.dart';
import '../patch_node_spec.dart';
import '../patcher_controller.dart';

/// Creates one catalogue object on the canvas as a single undoable step — the
/// journaled half of both authoring gestures that mint an object: the palette
/// drag-drop (design `docs/design/patcher.md` §5) and the inline object box
/// (issue #358).
///
/// Creation was the one canvas verb that stayed off the stack: everything else a
/// patch can do — move, connect, delete, duplicate, re-param — round-trips under
/// Ctrl+Z, so an object that could not be un-created was the odd one out, and the
/// typing gesture (which mints objects a keystroke at a time) makes that gap
/// impossible to live with.
///
/// The first [apply] mints the object and captures its full [PatchNodeSpec];
/// [revert] deletes it; a **redo** restores it from that spec under the *same*
/// logical [PatchNodeId], so cables and any lower undo commands that named the
/// node survive an undo/redo cycle — the same discipline
/// `DeletePatchNodesCommand.revert` uses.
///
/// The fresh object becomes the selection, so the hand that just made it can
/// move, duplicate or delete it without reaching for the mouse; an undo takes
/// the node out of the graph, which drops it from the selection with it.
class CreatePatchObjectCommand implements ProjectCommand {
  CreatePatchObjectCommand(
    this.controller, {
    required this.desc,
    required this.args,
    required this.position,
    this.voice = 1,
  });

  final PatcherController controller;

  /// The catalogue entry to instantiate.
  final PatchObjectDescriptor desc;

  /// The creation-argument string to mint it with — already resolved against
  /// the type's documented parameters by the caller.
  final String args;

  /// Scene-space top-left the node lands at.
  final Offset position;

  final int voice;

  PatchNodeId? _id;
  PatchNodeSpec? _spec;

  /// The node this command created, once it has been applied. Null before the
  /// first [apply].
  PatchNodeId? get createdId => _id;

  @override
  String get label => 'create ${desc.type}';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    final id = _id;
    if (id == null) {
      final node = controller.addObject(
        desc: desc,
        position: position,
        args: args,
        voice: voice,
      );
      _id = node.id;
      _spec = controller.captureSpec(node.id);
    } else {
      controller.restoreNodePrimitive(id, _spec!);
    }
    controller.selectNodes({_id!});
  }

  @override
  void revert() {
    final id = _id;
    if (id != null) controller.deleteNodePrimitive(id);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_create_object',
    'object': desc.type,
    'args': args,
  };
}
