import 'package:flutter/painting.dart';

/// Phi corner radii. Small or zero; never pillowy.
abstract final class PhiRadii {
  // region: generated-from-css
  // Auto-generated from `design system/colors_and_type.css`.
  // Run `dart run tool/gen_tokens.dart` to refresh; `--check` to verify drift.

  static const Radius r0 = Radius.zero;
  static const Radius r1 = Radius.circular(2);
  static const Radius r2 = Radius.circular(4);
  static const Radius r3 = Radius.circular(6);
  static const Radius rPill = Radius.circular(999);
  // endregion: generated-from-css

  static const BorderRadius all1 = BorderRadius.all(r1);
  static const BorderRadius all2 = BorderRadius.all(r2);
  static const BorderRadius all3 = BorderRadius.all(r3);
  static const BorderRadius allPill = BorderRadius.all(rPill);
}
