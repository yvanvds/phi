import '../../../domain/patcher/patch_cable.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/project/project_command.dart';
import '../../bridge/patch_object_descriptor.dart';
import '../patch_node_spec.dart';
import '../patcher_controller.dart';

/// Replaces the object at one node with an object of **another type**, in place
/// — the retype gesture (design `docs/design/patcher.md` §7, issue #383).
///
/// Typing `saw 300` over a `sine 300` is not a reconfiguration: the engine has
/// no verb that turns one object into another, so the native object is deleted
/// and a new one is minted. What makes it an *edit* rather than a delete
/// followed by a create is everything that is carried across — the node keeps
/// its logical [PatchNodeId], its position, its selection, and every cable whose
/// endpoint still exists on the new object.
///
/// One journaled step, because that is how it is undone: [revert] puts the old
/// object back under the same id **and re-wires every cable the retype dropped**,
/// so a retype that cost the patch two connections costs nothing after one
/// `Ctrl+Z`. The capture refreshes on every [apply], so a redo after further
/// edits restores the then-current state — the same discipline
/// `DeletePatchNodesCommand` uses.
class RetypePatchObjectCommand implements ProjectCommand {
  RetypePatchObjectCommand(
    this.controller, {
    required this.id,
    required this.desc,
    required this.args,
  });

  final PatcherController controller;

  /// The node being retyped — the same logical id before and after, which is
  /// what keeps the surviving cables (and any lower undo command that named it)
  /// valid.
  final PatchNodeId id;

  /// The catalogue entry the box resolved — the type the object becomes.
  final PatchObjectDescriptor desc;

  /// The creation-argument string for the new type, already checked against its
  /// documented parameters (`PatchCreationArgs`) by the caller.
  final String args;

  /// The object as it was before the last [apply] — what [revert] mints again.
  PatchNodeSpec? _before;

  /// Cables the last [apply] could not carry over — reported so the canvas can
  /// say what the retype cost, and re-wired by [revert] (issue #383).
  List<PatchCable> _dropped = const [];

  /// How many connections the retype could not carry. Zero before the first
  /// [apply], and after an undo of it.
  int get droppedCount => _dropped.length;

  @override
  String get label => 'retype as ${desc.type}';

  @override
  Set<EntityAddress> get entitiesTouched => const {};

  @override
  void apply() {
    _before = controller.captureSpec(id);
    _dropped = controller.retypeNodePrimitive(id, type: desc.type, args: args);
  }

  @override
  void revert() {
    final before = _before;
    if (before == null) return;
    // Back to the old object under the same id. The retype is symmetric, so the
    // cables that survived the apply survive this one too — carried across by
    // the primitive itself. Only the ones it had to drop need wiring again, and
    // the old object is exactly the one that has room for them.
    controller.retypeNodePrimitive(id, type: before.type, args: before.args);
    for (final cable in _dropped) {
      controller.addCablePrimitive(cable);
    }
    _dropped = const [];
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'patch_retype_object',
    'object': desc.type,
    'args': args,
  };
}
