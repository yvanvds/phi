import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// The `.textbutton` object drawn as **only itself**: a labelled button, drawn
/// pressed — filled and outlined in the voice colour — while its state is on
/// (issue #470).
///
/// The engine's `.textbutton` is `.led`'s value model under another name; what
/// differs is only this drawing, a rounded button carrying its label in the
/// middle rather than a lamp with the label beside it.
///
/// Visual-only: the press belongs to the caller, so the button stays inert
/// chrome while the canvas is in edit mode (issue #378).
class PatchTextButton extends StatelessWidget {
  const PatchTextButton({
    required this.pressed,
    required this.label,
    required this.voice,
    super.key,
  });

  /// Whether the button is drawn pressed (its state is on).
  final bool pressed;

  /// The button's text; an unlabelled button shows nothing in it.
  final String label;

  /// Voice index in `[1, 6]`; the pressed button takes its colour.
  final int voice;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pressed ? PhiVoices.glow(voice) : PhiColors.bg2,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: pressed ? color : PhiColors.line2),
        boxShadow: pressed
            ? [BoxShadow(color: PhiVoices.glow(voice), blurRadius: 10)]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PatchCanvasConstants.objectBoxPaddingH,
        ),
        child: Center(
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              color: pressed ? PhiColors.fg0 : PhiColors.fg1,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
