import 'package:flutter/animation.dart';

/// Phi motion tokens.
///
/// Motion is signal-like: fast attack, exponential decay. Never bouncy.
/// `easeOut` covers ~95% of UI motion.
abstract final class PhiMotion {
  // region: generated-from-css
  // Auto-generated from `design system/colors_and_type.css`.
  // Run `dart run tool/gen_tokens.dart` to refresh; `--check` to verify drift.

  static const Cubic easeOut = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Cubic easeIn = Cubic(0.7, 0.0, 0.84, 0.0);
  static const Cubic easeInOut = Cubic(0.65, 0.0, 0.35, 1.0);

  static const Duration dur1 = Duration(milliseconds: 90);
  static const Duration dur2 = Duration(milliseconds: 160);
  static const Duration dur3 = Duration(milliseconds: 280);
  static const Duration dur4 = Duration(milliseconds: 480);
  // endregion: generated-from-css
}
