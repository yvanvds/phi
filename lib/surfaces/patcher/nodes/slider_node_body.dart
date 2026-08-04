import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_voices.dart';
import '../../../design/widgets/fader/phi_fader.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.slider` node — a live [PhiFader] whose value is pushed to the
/// underlying control object via [PatcherController.setControlValue]
/// (`sendFloat`), its readout reflecting the value the native side reports back
/// through `guiValue` (design `docs/design/patcher.md` §7).
///
/// The generalising base of the live-GUI-body set: the fader seeds from the
/// object's current `guiValue`, so a reopened patch shows the slider where it
/// was left, and the display is the authoritative engine value rather than a
/// Dart-side guess.
///
/// It also **follows the engine**: a [GuiValueLink] reports every inbound value
/// — a cable, a script, another editor — and the thumb moves to it (issue
/// #357). Only while the user has hold of the thumb is that suspended, from the
/// first [PhiFader.onChanged] to [PhiFader.onChangeEnd]: a poll landing
/// mid-drag would otherwise fight the pointer for the control. The suspension
/// ends with the gesture, not the argument — on release the object is asked
/// once more and wins, so a drag that overlapped a cable settles on what the
/// patch actually holds rather than on where the hand happened to stop.
class SliderNodeBody extends StatefulWidget {
  const SliderNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  @override
  State<SliderNodeBody> createState() => _SliderNodeBodyState();
}

class _SliderNodeBodyState extends State<SliderNodeBody> {
  /// Where the object sits before it has ever reported a value.
  static const double _defaultValue = 0.5;

  late final GuiValueLink _gui;
  late double _value;

  /// True from the first push of a gesture until its release — the window in
  /// which the thumb belongs to the pointer and not to the engine.
  bool _held = false;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _value = _parse(_gui.value) ?? _defaultValue;
  }

  @override
  void didUpdateWidget(SliderNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    _gui.dispose();
    super.dispose();
  }

  /// The engine reported a new value: move the thumb to it, unless the user is
  /// the one moving it.
  void _follow(String raw) {
    if (_held) return;
    final v = _parse(raw);
    if (v == null || v == _value) return;
    setState(() => _value = v);
  }

  static double? _parse(String raw) => double.tryParse(raw)?.clamp(0.0, 1.0);

  void _push(double v) {
    setState(() {
      _held = true;
      _value = v;
    });
    widget.controller.setControlValue(widget.node.id, inlet: 0, value: v);
  }

  /// Hand the thumb back to the engine and re-read it once.
  ///
  /// The poll cannot do this for us: it already saw every value the drag pushed
  /// and updated its own record, so anything that landed on the object while
  /// the thumb was held — a cable firing into it, a clamp the object applied —
  /// would sit there unreported until the *next* change. Re-reading on release
  /// costs one comparison and is silent whenever the engine agrees, which is
  /// the ordinary case.
  void _release() {
    if (!_held) return;
    final v = _parse(_gui.value);
    setState(() {
      _held = false;
      if (v != null) _value = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PhiFader(
        value: _value,
        height: 110,
        readout: _readout(),
        voiceColor: PhiVoices.color(widget.node.voice),
        voiceGlow: PhiVoices.glow(widget.node.voice),
        onChanged: _push,
        onChangeEnd: _release,
      ),
    );
  }

  /// The engine's reported display value, falling back to the local position
  /// before the first push has landed a `guiValue`.
  String _readout() {
    final v = double.tryParse(_gui.value) ?? _value;
    return v.toStringAsFixed(2);
  }
}
