/// Phi spacing scale (4px base; see `design system/colors_and_type.css`).
abstract final class PhiSpacing {
  // region: generated-from-css
  // Auto-generated from `design system/colors_and_type.css`.
  // Run `dart run tool/gen_tokens.dart` to refresh; `--check` to verify drift.

  static const double s0 = 2;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
  static const double s7 = 48;
  static const double s8 = 64;
  static const double s9 = 96;

  /// 16px backdrop grid cell, used in 3D viewport / patcher / state graph.
  static const double gridCell = 16;
  // endregion: generated-from-css

  /// Chrome region sizes (from `design system/ui_kits/phi-workstation/`).
  static const double topToolbarHeight = 36;
  static const double leftRailWidth = 48;
  static const double rightInspectorCollapsedWidth = 28;
  static const double rightInspectorExpandedWidth = 320;
  static const double bottomStatusHeight = 24;
}
