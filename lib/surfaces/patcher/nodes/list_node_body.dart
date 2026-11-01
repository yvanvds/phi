import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_list_box.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.l` (list box) node — a clickable [PatchListBox] showing the
/// list the object stores, which a tap sends through
/// [PatcherController.setControlBang] (`sendBang` on the hot inlet), the
/// message-box gesture (issue #470).
///
/// Unlike a `.m`, whose text is its creation arguments, a list box's content
/// is **live**: a list arriving on its inlet replaces it without sending. So
/// the box shows the object's `guiValue` — its stored list — and a
/// [GuiValueLink] keeps it current, so a list set over a cable shows up
/// without a click. An empty list shows a dim placeholder.
class ListNodeBody extends StatefulWidget {
  const ListNodeBody({required this.node, required this.controller, super.key});

  final PatchNode node;
  final PatcherController controller;

  @override
  State<ListNodeBody> createState() => _ListNodeBodyState();
}

class _ListNodeBodyState extends State<ListNodeBody> {
  late final GuiValueLink _gui;
  late String _list;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _list = _gui.value.trim();
  }

  @override
  void didUpdateWidget(ListNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  void _follow(String raw) {
    final list = raw.trim();
    if (list == _list) return;
    setState(() => _list = list);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.controller.setControlBang(widget.node.id, inlet: 0),
      child: PatchListBox(
        child: Text(
          _list.isEmpty ? 'list' : _list,
          style: PhiType.monoS().copyWith(
            color: _list.isEmpty ? PhiColors.fg3 : PhiColors.fg0,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
