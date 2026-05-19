import 'package:flutter/widgets.dart';

import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// The 8px voice-coloured dot at the edge of a node where a cable
/// terminates. Visual only — gesture handling is layered on by the
/// surface (a `Listener` wrapper for output dots, plain hit-testing for
/// input dots).
class PatchPortDot extends StatelessWidget {
  const PatchPortDot({required this.voice, this.dim = false, super.key});

  /// Voice index in `[1, 6]`.
  final int voice;

  /// When true, drop the glow for a more inert look (e.g. while dragging
  /// a different port). Not used in the first PR.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    return Container(
      width: PatchCanvasConstants.portDotSize,
      height: PatchCanvasConstants.portDotSize,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: dim
            ? null
            : [
                BoxShadow(
                  color: PhiVoices.glow(voice),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
      ),
    );
  }
}
