import 'package:flutter/widgets.dart';

import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';
import 'patch_port_dot.dart';

/// A **GUI object** on the canvas: its own control, and nothing else (design
/// §7, §12.2, issue #381).
///
/// The counterpart of [PatchObjectBox] for the interactive control types. Where
/// the object box is a bordered line of text, a GUI object is a bang, a toggle,
/// a fader, a readout or a message — each of which already says what it is, so
/// there is nothing left for a caption to add. What this widget contributes is
/// therefore deliberately almost nothing: it does **not** draw a frame, a fill,
/// a border or a header. It seats the control in the node's rectangle and hangs
/// the ports off the **top** edge (inlets) and the **bottom** edge (outlets) at
/// the supplied pixel offsets (issue #377), which is the one piece of chrome the
/// control itself cannot carry.
///
/// The armed state is the second: a node that is armed glows in its voice, as it
/// does everywhere else in the app. With no frame to voice, the glow is drawn
/// *behind* the control rather than as a border around it.
///
/// Visual-only and unaware of `PatchNode`/`PatcherController`; whether the
/// control answers a press at all is the canvas's **mode** (issue #378), which
/// the caller applies above this widget.
class PatchGuiObject extends StatelessWidget {
  const PatchGuiObject({
    required this.voice,
    required this.armed,
    required this.inputPortXs,
    required this.outputPortXs,
    required this.inputVoices,
    required this.outputVoices,
    required this.child,
    super.key,
  });

  /// Voice index in `[1, 6]` used for the armed glow.
  final int voice;

  /// When true, draws a faint voiced glow under the control.
  final bool armed;

  /// X-position of each input port centre along the **top** edge, measured from
  /// the left of the node. Length matches the number of inputs.
  final List<double> inputPortXs;

  /// X-position of each output port centre along the **bottom** edge, measured
  /// from the left of the node.
  final List<double> outputPortXs;

  /// Voice index per input port. Length matches [inputPortXs].
  final List<int> inputVoices;

  /// Voice index per output port. Length matches [outputPortXs].
  final List<int> outputVoices;

  /// The control itself, stretched to fill the node's rectangle.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (armed)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(color: PhiVoices.glow(voice), blurRadius: 16),
                ],
              ),
            ),
          ),
        child,
        for (var i = 0; i < inputPortXs.length; i++)
          Positioned(
            left: inputPortXs[i] - PatchCanvasConstants.portDotRadius,
            top: -PatchCanvasConstants.portDotRadius,
            child: PatchPortDot(voice: inputVoices[i]),
          ),
        for (var i = 0; i < outputPortXs.length; i++)
          Positioned(
            left: outputPortXs[i] - PatchCanvasConstants.portDotRadius,
            bottom: -PatchCanvasConstants.portDotRadius,
            child: PatchPortDot(voice: outputVoices[i]),
          ),
      ],
    );
  }
}
