import 'package:flutter/painting.dart';

import '../../tokens/phi_colors.dart';

/// The colour an object's name is written in — the one thing that says DSP or
/// control now that the `~`/`.` prefix is no longer drawn (design §5, §12.4,
/// issue #380).
///
/// One place, because the fact has to read the same on the canvas box, in the
/// palette, in the completion list and on the reference panel's heading; four
/// copies of `isDsp ? cool : fg1` would drift the first time one of them was
/// tuned.
///
/// [PhiColors.cool] is not a new meaning: it is the blue an audio cable is
/// already drawn in and the blue the overview already uses for DSP, so a patch
/// reads as one system rather than as a legend to memorise.
abstract final class PatchTypeStyle {
  /// The name colour for a DSP ([isDsp]) or control object.
  static Color color(bool isDsp) => isDsp ? PhiColors.cool : PhiColors.fg1;
}
