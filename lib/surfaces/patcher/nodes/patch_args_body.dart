import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../domain/patcher/patch_node_id.dart';
import '../../../engine/state/patcher_controller.dart';

/// Default body for a node with **no hand-authored GUI body**: the object's
/// type followed by its creation arguments, the way a Max object box reads —
/// `~sine 440`, `.metro 250` (issue #356).
///
/// Before this, a drag-created engine object rendered an empty box, so a patch
/// of them was unreadable at a glance: nothing on the canvas said what any
/// object was set to, and applying the params dialog changed what was sounding
/// while the canvas stayed blank.
///
/// The arguments are read from the controller on every build and never cached,
/// so an apply — and its undo/redo, which all run through
/// `PatcherController.setNodeParams` and its [PatchNode.markParamsChanged]
/// wake-up — repaints this body with the new value. One line, ellipsised: the
/// box is only as tall as its ports need, and the reference panel is where a
/// long argument list is read in full.
class PatchArgsBody extends StatelessWidget {
  const PatchArgsBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// Key on one node's rendered argument line, so a test can name the body of
  /// a specific node on a canvas full of them.
  static Key lineKey(PatchNodeId id) => Key('PatchArgsBody.${id.value}');

  @override
  Widget build(BuildContext context) {
    final args = controller.argsOf(node.id).trim();
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        args.isEmpty ? node.type : '${node.type} $args',
        key: lineKey(node.id),
        style: PhiType.monoS().copyWith(color: PhiColors.fg2),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
