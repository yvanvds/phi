import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_voices.dart';
import '../../../design/widgets/fader/phi_fader.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.slider` node — a live [PhiFader] whose value is pushed to the
/// underlying control object via [PatcherController.setControlValue]
/// (`sendFloat`), its readout reflecting the value the native side reports back
/// through `guiValue` (design `docs/design/patcher.md` §7).
///
/// The generalising base of the live-GUI-body set: the fader seeds from the
/// object's current `guiValue`, so a reopened patch shows the slider where it
/// was left, and re-reads it after each push so the readout is the authoritative
/// engine value, not a Dart-side guess.
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
  late double _value = _seed();

  double _seed() {
    final gui = double.tryParse(widget.controller.guiValueOf(widget.node.id));
    if (gui == null) return 0.5;
    return gui.clamp(0.0, 1.0);
  }

  void _push(double v) {
    setState(() => _value = v);
    widget.controller.setControlValue(widget.node.id, inlet: 0, value: v);
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
      ),
    );
  }

  /// The engine's reported display value, falling back to the local position
  /// before the first push has landed a `guiValue`.
  String _readout() {
    final gui = widget.controller.guiValueOf(widget.node.id);
    final v = double.tryParse(gui) ?? _value;
    return v.toStringAsFixed(2);
  }
}
