import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';
import 'patch_port_dot.dart';

/// Visual chrome for one node: 22px uppercase mono header, a body slot
/// underneath, voice-coloured 1px border that lights up when [armed],
/// and ports protruding from the left and right edges at the supplied
/// pixel offsets.
///
/// Visual-only and unaware of [PatchNode]/[PatcherController]; callers
/// wrap it in a `GestureDetector`/`Listener` for drag and tap.
class PatchNodeFrame extends StatelessWidget {
  const PatchNodeFrame({
    required this.title,
    required this.voice,
    required this.armed,
    required this.inputPortYs,
    required this.outputPortYs,
    required this.inputVoices,
    required this.outputVoices,
    required this.body,
    super.key,
  });

  /// Header text — already display-ready (lowercase mono `osc · sine`
  /// style); the widget upper-cases nothing.
  final String title;

  /// Voice index in `[1, 6]` used for the armed border + header glow.
  final int voice;

  /// When true, draws a voiced 1px border and a faint glow underneath.
  final bool armed;

  /// Y-position of each input port centre, measured from the top of the
  /// frame. Length matches the number of inputs.
  final List<double> inputPortYs;

  /// Y-position of each output port centre, measured from the top of
  /// the frame.
  final List<double> outputPortYs;

  /// Voice index per input port. Length matches [inputPortYs].
  final List<int> inputVoices;

  /// Voice index per output port. Length matches [outputPortYs].
  final List<int> outputVoices;

  /// Body widget drawn below the header.
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final voiceColor = PhiVoices.color(voice);
    final voiceGlow = PhiVoices.glow(voice);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(
              color: armed ? voiceColor : PhiColors.line1,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: armed
                ? [BoxShadow(color: voiceGlow, blurRadius: 16)]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: title, armed: armed, voice: voice),
              Expanded(child: body),
            ],
          ),
        ),
        for (var i = 0; i < inputPortYs.length; i++)
          Positioned(
            left: -PatchCanvasConstants.portDotRadius,
            top: inputPortYs[i] - PatchCanvasConstants.portDotRadius,
            child: PatchPortDot(voice: inputVoices[i]),
          ),
        for (var i = 0; i < outputPortYs.length; i++)
          Positioned(
            right: -PatchCanvasConstants.portDotRadius,
            top: outputPortYs[i] - PatchCanvasConstants.portDotRadius,
            child: PatchPortDot(voice: outputVoices[i]),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.armed,
    required this.voice,
  });

  final String title;
  final bool armed;
  final int voice;

  @override
  Widget build(BuildContext context) {
    final color = armed ? PhiVoices.color(voice) : PhiColors.fg2;
    return Container(
      height: PatchCanvasConstants.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: PhiColors.bg2,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: PhiType.caption().copyWith(
          color: color,
          fontSize: 9,
          shadows: armed
              ? [Shadow(color: PhiVoices.glow(voice), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }
}
