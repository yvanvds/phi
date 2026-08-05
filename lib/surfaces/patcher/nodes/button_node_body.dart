import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_bang_square.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.b` (button / bang) node — a momentary trigger that fires a
/// bang into the object's hot inlet via [PatcherController.setControlBang]
/// (`sendBang`) on tap, flashing briefly in the node's voice colour (design
/// `docs/design/patcher.md` §7).
///
/// Since issue #381 the node **is** the square: no header, no frame, no `bang`
/// caption inside it, and no padding around it — the [PatchBangSquare] fills the
/// node's whole rectangle. The wiring is untouched: the same `sendBang` on the
/// same hot inlet, and the same brief flash to acknowledge it.
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
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _bang() {
    widget.controller.setControlBang(widget.node.id, inlet: 0);
    setState(() => _flash = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 120), () {
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
