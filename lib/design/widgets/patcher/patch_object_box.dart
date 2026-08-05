import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';
import 'patch_object_box_metrics.dart';
import 'patch_port_dot.dart';

/// An engine object on the canvas: **one bordered line of mono text**, and
/// nothing else (design §7, §12.2, issue #379).
///
/// What it replaces was a 22px uppercase header carrying a display title
/// (`OSC · SINE`) over a body printing roughly the same thing again with its
/// arguments (`~sine 440`) — two rows and ~70px of canvas for one line's worth
/// of information. The object *is* the box now: the title is not rendered at
/// all, because `~sine 440` names itself.
///
/// The chrome that survives is the chrome that says something the text cannot:
/// a 1px border that goes voiced and glows while the node is armed, and the
/// ports protruding from the **top** edge (inlets) and the **bottom** edge
/// (outlets) at the supplied pixel offsets (issue #377) — which is what lets
/// the box be one line tall in the first place.
///
/// Sized by its caller from [PatchObjectBoxMetrics], not by its own layout:
/// the node's rectangle is model state the cables are drawn against, so it is
/// measured before the frame rather than discovered during it. The line
/// ellipsises when the box it is given cannot hold it.
///
/// Visual-only and unaware of `PatchNode`/`PatcherController`; the canvas's raw
/// pointer pipeline owns every press over it.
class PatchObjectBox extends StatelessWidget {
  const PatchObjectBox({
    required this.text,
    required this.voice,
    required this.armed,
    required this.inputPortXs,
    required this.outputPortXs,
    required this.inputVoices,
    required this.outputVoices,
    this.textKey,
    super.key,
  });

  /// The object's line — display-ready, `~sine 440` style. Dropping the type
  /// prefix and colouring the line by DSP/control is issue #380; this widget
  /// prints what it is handed.
  final String text;

  /// Voice index in `[1, 6]` used for the armed border + glow.
  final int voice;

  /// When true, draws a voiced 1px border and a faint glow underneath.
  final bool armed;

  /// X-position of each input port centre along the **top** edge, measured
  /// from the left of the box. Length matches the number of inputs.
  final List<double> inputPortXs;

  /// X-position of each output port centre along the **bottom** edge, measured
  /// from the left of the box.
  final List<double> outputPortXs;

  /// Voice index per input port. Length matches [inputPortXs].
  final List<int> inputVoices;

  /// Voice index per output port. Length matches [outputPortXs].
  final List<int> outputVoices;

  /// Key placed on the rendered line, so a test can name the text of one
  /// specific node on a canvas full of them.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final voiceColor = PhiVoices.color(voice);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(
              color: armed ? voiceColor : PhiColors.line1,
              width: PatchCanvasConstants.nodeBorderWidth,
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: armed
                ? [BoxShadow(color: PhiVoices.glow(voice), blurRadius: 16)]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PatchCanvasConstants.objectBoxPaddingH,
              vertical: PatchCanvasConstants.objectBoxPaddingV,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                key: textKey,
                // The very style the box was measured with — see
                // [PatchObjectBoxMetrics.lineStyle].
                style: PatchObjectBoxMetrics.lineStyle().copyWith(
                  color: PhiColors.fg1,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
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
