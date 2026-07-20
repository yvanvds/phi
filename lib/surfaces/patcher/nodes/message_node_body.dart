import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.m` (message) node — a clickable box showing the stored
/// message that fires it into the graph on tap via
/// [PatcherController.setControlBang] (`sendBang` on the hot inlet), the Max
/// message-box gesture (design `docs/design/patcher.md` §7).
///
/// The message content is the object's creation-argument string (what the
/// params dialog edits); an empty message shows a dim placeholder.
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
      child: Container(
        decoration: BoxDecoration(
          color: PhiColors.bg2,
          borderRadius: PhiRadii.all1,
          border: Border.all(color: PhiColors.line2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        alignment: Alignment.centerLeft,
        child: Text(
          message.isEmpty ? 'message' : message,
          style: PhiType.monoS().copyWith(
            color: message.isEmpty ? PhiColors.fg3 : PhiColors.fg0,
          ),
        ),
      ),
    );
  }
}
