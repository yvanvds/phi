import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_voices.dart';
import '../../../design/widgets/fader/phi_fader.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.slider` node — a live [PhiFader] whose value is pushed
/// to the underlying control object via [PatcherController.setControlValue].
///
/// The fader's value lives in widget state for the first PR; persistence
/// to the native side's GUI properties is a follow-up.
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
  double _value = 0.5;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PhiFader(
        value: _value,
        height: 110,
        voiceColor: PhiVoices.color(widget.node.voice),
        voiceGlow: PhiVoices.glow(widget.node.voice),
        onChanged: (v) {
          setState(() => _value = v);
          widget.controller.setControlValue(widget.node.id, inlet: 0, value: v);
        },
      ),
    );
  }
}
