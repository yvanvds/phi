import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_type.dart';
import '../../tokens/phi_voices.dart';
import 'patch_canvas_constants.dart';

/// The `.led` object drawn as **only itself**: a round lamp with the control's
/// label beside it (issue #470).
///
/// The label is the point of the object — the engine's `.led` exists so a
/// switch can say what it is — so it is printed on the node, in the same small
/// mono an object box uses. Unlit, the lamp is a dim ring; lit, it fills with
/// the voice colour and glows.
///
/// Visual-only: the press belongs to the caller, so the lamp stays inert chrome
/// while the canvas is in edit mode (issue #378).
class PatchLedLamp extends StatelessWidget {
  const PatchLedLamp({
    required this.on,
    required this.label,
    required this.voice,
    super.key,
  });

  /// Whether the lamp is lit.
  final bool on;

  /// The control's name; empty draws the lamp alone.
  final String label;

  /// Voice index in `[1, 6]`; the lit lamp takes its colour.
  final int voice;

  /// The lamp's diameter as a fraction of the node's height.
  static const double lampFraction = 0.6;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PatchCanvasConstants.objectBoxPaddingH,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final lamp = constraints.hasBoundedHeight
                ? constraints.maxHeight * lampFraction
                : 12.0;
            return Row(
              children: [
                SizedBox.square(
                  dimension: lamp,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? color : PhiColors.bg2,
                      border: Border.all(color: on ? color : PhiColors.line2),
                      boxShadow: on
                          ? [
                              BoxShadow(
                                color: PhiVoices.glow(voice),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                if (label.isNotEmpty) ...[
                  const SizedBox(width: PatchCanvasConstants.objectBoxPaddingH),
                  Expanded(
                    child: Text(
                      label,
                      style: PhiType.monoS().copyWith(
                        color: on ? PhiColors.fg0 : PhiColors.fg1,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
