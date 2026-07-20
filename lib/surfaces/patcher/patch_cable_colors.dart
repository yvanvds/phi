import 'package:flutter/painting.dart';

import '../../design/tokens/phi_colors.dart';
import '../../engine/bridge/patch_object_descriptor.dart';

/// Colour an outlet's data type paints its cable with (design
/// `docs/design/patcher.md` §6, "the ghost cable colours by the outlet's
/// `OutType`"). Signal (`buffer`) wears the cool audio accent that the palette's
/// DSP badge also uses; control types get distinct, legible hues.
Color patchOutletColor(PatchOutletType type) {
  switch (type) {
    case PatchOutletType.buffer:
      return PhiColors.cool;
    case PatchOutletType.float:
      return PhiColors.voice4;
    case PatchOutletType.integer:
      return PhiColors.voice3;
    case PatchOutletType.bang:
      return PhiColors.voice1;
    case PatchOutletType.list:
      return PhiColors.voice5;
    case PatchOutletType.any:
      return PhiColors.fg1;
    case PatchOutletType.invalid:
      return PhiColors.fg3;
  }
}

/// The soft glow-shell colour for [type]'s cable — the same hue at low alpha.
Color patchOutletGlow(PatchOutletType type) =>
    patchOutletColor(type).withValues(alpha: 0.3);
