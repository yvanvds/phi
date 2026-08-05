import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_message_box.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.m` (message) node — a clickable box showing the stored
/// message that fires it into the graph on tap via
/// [PatcherController.setControlBang] (`sendBang` on the hot inlet), the Max
/// message-box gesture (design `docs/design/patcher.md` §7).
///
/// The message content is the object's creation-argument string (what the
/// params dialog edits); an empty message shows a dim placeholder.
///
/// Since issue #381 the node **is** the message box: no `MESSAGE` header, no
/// frame, no padding — a [PatchMessageBox] fills the node's rectangle, and its
/// notched right edge is what says "message" now that no caption does.
class MessageNodeBody extends StatelessWidget {
  const MessageNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  Widget build(BuildContext context) {
    final message = controller.argsOf(node.id).trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.setControlBang(node.id, inlet: 0),
      child: PatchMessageBox(
        child: Text(
          message.isEmpty ? 'message' : message,
          style: PhiType.monoS().copyWith(
            color: message.isEmpty ? PhiColors.fg3 : PhiColors.fg0,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
