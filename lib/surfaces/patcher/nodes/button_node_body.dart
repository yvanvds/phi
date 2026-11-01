import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_bang_square.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.b` (button / bang) node — a momentary trigger that fires a
/// bang into the object's hot inlet via [PatcherController.setControlBang]
/// (`sendBang`) on tap, flashing briefly in the node's voice colour (design
/// `docs/design/patcher.md` §7).
///
/// Since issue #381 the node **is** the square: no header, no frame, no `bang`
/// caption inside it, and no padding around it — the [PatchBangSquare] fills the
/// node's whole rectangle.
///
/// It also flashes for a press that arrives over a **cable** — a `.metro` tick,
/// say (issue #519). The engine's `.b` lights until the host next reads it: its
/// `guiValue` reports `on` once for each pending press and `off` after, and the
/// read clears the press. So the body never reads the engine itself; it follows
/// the surface's poll through a [GuiValueLink], which hands it the one read the
/// poll made, and flashes whenever that read says `on`.
class ButtonNodeBody extends StatefulWidget {
  const ButtonNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<ButtonNodeBody> createState() => _ButtonNodeBodyState();
}

class _ButtonNodeBodyState extends State<ButtonNodeBody> {
  /// How long a press stays lit.
  static const Duration _flashTime = Duration(milliseconds: 120);

  late final GuiValueLink _gui;
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    // No seeding read: the value is an event, not a state, and reading it here
    // would swallow a press the poll should report.
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
  }

  @override
  void didUpdateWidget(ButtonNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _gui.dispose();
    super.dispose();
  }

  /// The engine spells a pending press `on` and an idle button `off`.
  void _follow(String raw) {
    if (raw.trim() == 'on') _flashOnce();
  }

  void _bang() {
    widget.controller.setControlBang(widget.node.id, inlet: 0);
    _flashOnce();
  }

  void _flashOnce() {
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(_flashTime, () {
      if (mounted) setState(() => _flash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _bang,
      child: PatchBangSquare(flash: _flash, voice: widget.node.voice),
    );
  }
}
