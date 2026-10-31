import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../design/widgets/patcher/patch_led_lamp.dart';
import '../../../design/widgets/patcher/patch_text_button.dart';
import '../../../domain/patcher/label_switch_args.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the two labelled on/off objects, `.led` (a [PatchLedLamp]) and
/// `.textbutton` (a [PatchTextButton]) — one body for both, because the engine
/// gives them one implementation and one protocol (`gLabelSwitchBase`): only
/// the drawing differs (issue #470).
///
/// Both read `[momentary] label…` from their creation arguments
/// ([LabelSwitchArgs]), each build, so a retyped label shows at once.
///
/// - **Latching** (the default): a click flips the state optimistically and
///   pushes it as an int through [PatcherController.setControlInt] — `1` on,
///   `0` off, which is what inlet 0 takes as a state. The engine's value lands
///   through a [GuiValueLink] a moment later and overrules the guess if the
///   object disagreed, and a state set over a cable shows the same way.
/// - **Momentary**: pressing sends a press (an int — any number is one) and the
///   control is drawn on for as long as the pointer is down. An inbound press —
///   the engine reports one pending press, then clears it — lights it for a
///   moment, the way a `.b` flashes.
class LabelSwitchNodeBody extends StatefulWidget {
  /// The `.led` body: a lamp with its label beside it.
  const LabelSwitchNodeBody.led({
    required this.node,
    required this.controller,
    super.key,
  }) : _lamp = true;

  /// The `.textbutton` body: a labelled button, drawn pressed while on.
  const LabelSwitchNodeBody.textButton({
    required this.node,
    required this.controller,
    super.key,
  }) : _lamp = false;

  final PatchNode node;
  final PatcherController controller;
  final bool _lamp;

  @override
  State<LabelSwitchNodeBody> createState() => _LabelSwitchNodeBodyState();
}

class _LabelSwitchNodeBodyState extends State<LabelSwitchNodeBody> {
  /// How long an inbound momentary press stays lit — a `.b`'s flash.
  static const Duration _flashTime = Duration(milliseconds: 120);

  late final GuiValueLink _gui;

  /// The engine's state (latching) or a press being flashed (momentary).
  late bool _on;

  /// Whether the pointer is holding a momentary control down.
  bool _held = false;

  Timer? _flashTimer;

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
  void didUpdateWidget(LabelSwitchNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _gui.dispose();
    super.dispose();
  }

  LabelSwitchArgs get _args =>
      LabelSwitchArgs.parse(widget.controller.argsOf(widget.node.id));

  /// The engine spells the state `1` / `0`; anything else non-zero is on.
  static bool _parse(String raw) => (double.tryParse(raw.trim()) ?? 0) != 0;

  void _follow(String raw) {
    final on = _parse(raw);
    if (_args.momentary) {
      if (on) _flash();
      return;
    }
    if (on == _on) return;
    setState(() => _on = on);
  }

  void _flash() {
    setState(() => _on = true);
    _flashTimer?.cancel();
    _flashTimer = Timer(_flashTime, () {
      if (mounted) setState(() => _on = false);
    });
  }

  void _toggle() {
    final next = !_on;
    setState(() => _on = next);
    widget.controller.setControlInt(
      widget.node.id,
      inlet: 0,
      value: next ? 1 : 0,
    );
  }

  void _press() {
    setState(() => _held = true);
    widget.controller.setControlInt(widget.node.id, inlet: 0, value: 1);
  }

  void _releasePress() {
    if (!_held) return;
    setState(() => _held = false);
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    final lit = _on || _held;
    final face = widget._lamp
        ? PatchLedLamp(on: lit, label: args.label, voice: widget.node.voice)
        : PatchTextButton(
            pressed: lit,
            label: args.label,
            voice: widget.node.voice,
          );
    if (args.momentary) {
      // A raw [Listener]: a press is a press the instant the pointer lands,
      // with no tap recogniser's arena delay between the finger and the sound.
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _press(),
        onPointerUp: (_) => _releasePress(),
        onPointerCancel: (_) => _releasePress(),
        child: face,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: face,
    );
  }
}
