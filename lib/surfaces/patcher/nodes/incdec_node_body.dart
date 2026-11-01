import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/patcher/patch_incdec_stepper.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.incdec` node — a live [PatchIncdecStepper]: a press on the
/// top half sends `inc`, on the bottom half `dec`, through
/// [PatcherController.sendControlMessage] into the hot inlet, and the box shows
/// the whole number the object holds (issue #470).
///
/// The step, the range and whether it wraps are the object's business (its
/// `step minimum maximum wrap` arguments); the body never does the arithmetic,
/// it reports. The value is the engine's `guiValue` — re-read straight after a
/// press so the click answers at once, and kept current between presses by a
/// [GuiValueLink], so a count driven over a cable (the nudge inlet, a `set`)
/// lands on the canvas too.
class IncdecNodeBody extends StatefulWidget {
  const IncdecNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// The selector a press on the top half sends.
  static const String incMessage = 'inc';

  /// The selector a press on the bottom half sends.
  static const String decMessage = 'dec';

  @override
  State<IncdecNodeBody> createState() => _IncdecNodeBodyState();
}

class _IncdecNodeBodyState extends State<IncdecNodeBody> {
  late final GuiValueLink _gui;
  late String _value;

  /// The half under a press in flight — `true` up, `false` down.
  bool? _pressed;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _value = _display(_gui.value);
  }

  @override
  void didUpdateWidget(IncdecNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  void _follow(String raw) {
    final v = _display(raw);
    if (v == _value) return;
    setState(() => _value = v);
  }

  /// An object that has never reported reads as its engine start, 0.
  static String _display(String raw) => raw.trim().isEmpty ? '0' : raw.trim();

  /// Arm the half under the press: above the node's midline is up.
  void _down(TapDownDetails d) {
    final height = context.size?.height ?? 0;
    setState(() => _pressed = d.localPosition.dy < height / 2);
  }

  void _step() {
    final up = _pressed;
    if (up == null) return;
    widget.controller.sendControlMessage(
      widget.node.id,
      inlet: 0,
      message: up ? IncdecNodeBody.incMessage : IncdecNodeBody.decMessage,
    );
    setState(() {
      _pressed = null;
      _value = _display(_gui.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: (_) => _step(),
      onTapCancel: () => setState(() => _pressed = null),
      child: PatchIncdecStepper(
        pressed: _pressed,
        voice: widget.node.voice,
        child: Text(
          _value,
          style: PhiType.monoS().copyWith(color: PhiColors.fg0),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
