import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_toggle_square.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.t` (toggle) node — a live [PatchToggleSquare] that pushes
/// `1`/`0` into the object's hot inlet via [PatcherController.setControlInt]
/// (`sendInt`), so flipping it on the canvas drives the graph (design
/// `docs/design/patcher.md` §7). An **int**, deliberately: the engine's
/// `gToggle` registers int and bang handlers on inlet 0 but no float one, and
/// its inlet dispatch never coerces — the float this body used to send was
/// silently dropped, so the canvas switch drove nothing and snapped back off
/// on the next poll (issue #439). With the int it is a working on/off switch
/// for anything int-driven — `.metro`'s start/stop above all.
///
/// Since issue #381 the node **is** the switch: no header, no frame, no padding
/// — the square fills the node's rectangle and carries a cross when it is on,
/// which is what a patcher toggle looks like and what reads across a canvas full
/// of them. Presentation only: every push, seed and inbound value below is
/// exactly as it was.
///
/// The on/off state seeds from the object's `guiValue`, so a reopened patch
/// shows the toggle where it was left, and a [GuiValueLink] keeps it there: an
/// inbound `1`/`0` — from a cable, a script, a `.b` upstream — flips the switch
/// on screen without anyone touching it (issue #357).
///
/// A tap flips optimistically and *then* pushes, rather than waiting to be told
/// what happened, so the switch never feels laggy under the finger; the engine's
/// own value lands a moment later through the same link and overrules it if the
/// object disagreed. There is no gesture to protect here — a toggle has no
/// in-between state for a poll to interrupt.
class ToggleNodeBody extends StatefulWidget {
  const ToggleNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<ToggleNodeBody> createState() => _ToggleNodeBodyState();
}

class _ToggleNodeBodyState extends State<ToggleNodeBody> {
  late final GuiValueLink _gui;
  late bool _on;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _on = _parse(_gui.value);
  }

  @override
  void didUpdateWidget(ToggleNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  void _follow(String raw) {
    final on = _parse(raw);
    if (on == _on) return;
    setState(() => _on = on);
  }

  /// The engine's `gToggle` reports its state as `on`/`off` (issue #439);
  /// a numeric report — from a fake, or a differently-shaped object — keeps
  /// the "anything non-zero is on" reading. An object that has never reported
  /// a value is off.
  static bool _parse(String raw) {
    if (raw == 'on') return true;
    if (raw == 'off') return false;
    return (double.tryParse(raw) ?? 0) != 0;
  }

  void _flip(bool value) {
    setState(() => _on = value);
    widget.controller.setControlInt(
      widget.node.id,
      inlet: 0,
      value: value ? 1 : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _flip(!_on),
      child: PatchToggleSquare(value: _on, voice: widget.node.voice),
    );
  }
}
