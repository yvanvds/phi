import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_dial_knob.dart';
import '../../../domain/patcher/dial_mapping.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.dial` node — a live [PatchDialKnob] whose 0–1 position is
/// pushed into the object's hot inlet via [PatcherController.setControlValue]
/// (`sendFloat`; the engine's `gDial` registers a float handler on inlet 0),
/// with the value the dial *sends* printed at its foot (issue #470).
///
/// The knob follows the engine the way the fader does: it seeds from the
/// object's `guiValue` — the position — and a [GuiValueLink] moves it on every
/// inbound value (a cable, a preset recall), except while the pointer has hold
/// of it, from the first drag update until release. Release re-reads once, so
/// a drag that overlapped a cable settles on what the object actually holds.
///
/// **Dragging** up turns it up and down turns it down, across
/// [_DialNodeBodyState._dragThrow] pixels for the full sweep — a vertical drag,
/// as on every knob in a patcher, because a circular one is unusable at this
/// size. The readout is the position put through the dial's own
/// `minimum maximum exponent intMode` ([DialMapping]), read from its creation
/// arguments each build, so retyping the range relabels the knob at once.
class DialNodeBody extends StatefulWidget {
  const DialNodeBody({required this.node, required this.controller, super.key});

  final PatchNode node;
  final PatcherController controller;

  @override
  State<DialNodeBody> createState() => _DialNodeBodyState();
}

class _DialNodeBodyState extends State<DialNodeBody> {
  /// Pixels of vertical drag that sweep the knob from one end to the other.
  static const double _dragThrow = 150;

  late final GuiValueLink _gui;
  late double _position;

  /// True from the first push of a drag until its release — the window in
  /// which the knob belongs to the pointer and not to the engine.
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _position = _parse(_gui.value) ?? 0;
  }

  @override
  void didUpdateWidget(DialNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  void _follow(String raw) {
    if (_held) return;
    final p = _parse(raw);
    if (p == null || p == _position) return;
    setState(() => _position = p);
  }

  static double? _parse(String raw) => double.tryParse(raw)?.clamp(0.0, 1.0);

  void _drag(DragUpdateDetails d) {
    final next = (_position - d.delta.dy / _dragThrow).clamp(0.0, 1.0);
    _held = true;
    if (next == _position) return;
    setState(() => _position = next);
    widget.controller.setControlValue(widget.node.id, inlet: 0, value: next);
  }

  void _release() {
    if (!_held) return;
    final p = _parse(_gui.value);
    setState(() {
      _held = false;
      if (p != null) _position = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mapping = DialMapping.fromArgs(
      widget.controller.argsOf(widget.node.id),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _drag,
      onVerticalDragEnd: (_) => _release(),
      onVerticalDragCancel: _release,
      child: PatchDialKnob(
        position: _position,
        readout: mapping.format(_position),
        voice: widget.node.voice,
      ),
    );
  }
}
