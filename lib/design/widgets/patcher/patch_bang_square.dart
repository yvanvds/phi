import 'package:flutter/widgets.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_voices.dart';

/// The `.b` object drawn as **only itself**: a square with a ring in it that
/// fills for a moment when the bang fires (design §7, issue #381).
///
/// What it replaces was a `BUTTON` header over a 40px square captioned `bang`
/// inside a 90×90 frame — three ways of saying one thing. A bang is a button;
/// nothing else needs to be on the canvas for that to read.
///
/// Visual-only: the tap that fires the bang belongs to the caller, which is what
/// keeps this widget usable as plain chrome while the canvas is in edit mode and
/// every body is inert (issue #378).
class PatchBangSquare extends StatelessWidget {
  const PatchBangSquare({required this.flash, required this.voice, super.key});

  /// True for the brief window after a bang fires — the square lights up in its
  /// voice colour, the only feedback a momentary trigger can give.
  final bool flash;

  /// Voice index in `[1, 6]`.
  final int voice;

  /// Diameter of the inner ring as a fraction of the square — Max's proportion,
  /// which leaves the ring readable at the small sizes a bang is drawn at.
  static const double _ringFraction = 0.6;

  @override
  Widget build(BuildContext context) {
    final color = PhiVoices.color(voice);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: flash ? color : PhiColors.line2),
        boxShadow: flash
            ? [BoxShadow(color: PhiVoices.glow(voice), blurRadius: 12)]
            : null,
      ),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: _ringFraction,
          heightFactor: _ringFraction,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: flash ? color : PhiColors.bg2,
              border: Border.all(color: flash ? color : PhiColors.line2),
            ),
          ),
        ),
      ),
    );
  }
}
