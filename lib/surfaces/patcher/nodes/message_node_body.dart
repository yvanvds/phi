import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_message_box.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.m` (message) node — a clickable box showing the stored
/// message that fires it into the graph on tap via
/// [PatcherController.setControlBang] (`sendBang` on the hot inlet), the Max
/// message-box gesture (design `docs/design/patcher.md` §7).
///
/// The text is the message the engine **holds now**, read from its `guiValue`
/// (issue #520): a list or a word message arriving on the inlet replaces it
/// without sending it, and the box follows that replacement through the
/// surface's GUI poll ([GuiValueLink]) so it always shows what a click sends.
/// The creation-argument string (what the params dialog edits and what the
/// patch saves) is only the fallback for an object the engine reports nothing
/// for; an empty message shows a dim placeholder.
///
/// Since issue #381 the node **is** the message box: no `MESSAGE` header, no
/// frame, no padding — a [PatchMessageBox] fills the node's rectangle, and its
/// notched right edge is what says "message" now that no caption does.
class MessageNodeBody extends StatefulWidget {
  const MessageNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<MessageNodeBody> createState() => _MessageNodeBodyState();
}

class _MessageNodeBodyState extends State<MessageNodeBody> {
  late final GuiValueLink _gui;
  late String _stored;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: (value) => setState(() => _stored = value),
    );
    // A `.m`'s read is not destructive, so seeding from it is safe.
    _stored = _gui.value;
  }

  @override
  void didUpdateWidget(MessageNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
    // New params re-parse the message; the controller marks the remembered
    // read stale, so this re-reads the engine once and then answers cached.
    _stored = _gui.value;
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final held = _stored.trim();
    final message = held.isEmpty
        ? widget.controller.argsOf(widget.node.id).trim()
        : held;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.controller.setControlBang(widget.node.id, inlet: 0),
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
