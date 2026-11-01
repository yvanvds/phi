import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_menu_box.dart';
import '../../../design/widgets/patcher/patch_radio_group.dart';
import '../../../design/widgets/patcher/patch_tab_strip.dart';
import '../../../domain/patcher/item_list_args.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';
import 'item_list_face.dart';

/// Body for the three selection controls, `.umenu` (a [PatchMenuBox]),
/// `.radiogroup` (a [PatchRadioGroup]) and `.tab` (a [PatchTabStrip]) — one
/// body for all three, because the engine gives them one implementation and one
/// protocol (`gItemListBase`): only the drawing differs (issue #471).
///
/// The items come from the creation arguments ([ItemListArgs]), read each
/// build, so a retyped item list shows at once.
///
/// Picking an item sends its number as an int through
/// [PatcherController.setControlInt] — "the user clicked item N", which selects
/// it, or with `multi` toggles it, and makes the object send. The body then
/// re-reads the engine's answer (the write marked the read stale), so what is
/// lit is always what the object holds. A selection set over a cable arrives
/// through a [GuiValueLink].
class ItemListNodeBody extends StatefulWidget {
  /// The `.umenu` body: a drop-down.
  const ItemListNodeBody.menu({
    required this.node,
    required this.controller,
    super.key,
  }) : _face = ItemListFace.menu;

  /// The `.radiogroup` body: radio buttons, or check boxes with `multi`.
  const ItemListNodeBody.radioGroup({
    required this.node,
    required this.controller,
    super.key,
  }) : _face = ItemListFace.radio;

  /// The `.tab` body: a row of tabs.
  const ItemListNodeBody.tabs({
    required this.node,
    required this.controller,
    super.key,
  }) : _face = ItemListFace.tabs;

  final PatchNode node;
  final PatcherController controller;
  final ItemListFace _face;

  @override
  State<ItemListNodeBody> createState() => _ItemListNodeBodyState();
}

class _ItemListNodeBodyState extends State<ItemListNodeBody> {
  late final GuiValueLink _gui;

  /// The engine's selection, as its GUI value spells it.
  late String _value;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _value = _gui.value;
  }

  @override
  void didUpdateWidget(ItemListNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  ItemListArgs get _args =>
      ItemListArgs.parse(widget.controller.argsOf(widget.node.id));

  void _follow(String raw) {
    if (raw == _value) return;
    setState(() => _value = raw);
  }

  void _pick(int item) {
    widget.controller.setControlInt(widget.node.id, inlet: 0, value: item);
    setState(() => _value = _gui.value);
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    final selected = args.selectionOf(_value);
    return switch (widget._face) {
      ItemListFace.menu => PatchMenuBox(
        labels: args.labels,
        selected: selected,
        multi: args.multi,
        onSelect: _pick,
      ),
      ItemListFace.radio => PatchRadioGroup(
        labels: args.labels,
        selected: selected,
        voice: widget.node.voice,
        multi: args.multi,
        onSelect: _pick,
      ),
      ItemListFace.tabs => PatchTabStrip(
        labels: args.labels,
        selected: selected,
        voice: widget.node.voice,
        onSelect: _pick,
      ),
    };
  }
}
