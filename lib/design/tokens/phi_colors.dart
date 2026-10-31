import 'package:flutter/painting.dart';

/// Phi colour tokens. Source of truth: `design system/colors_and_type.css`.
///
/// Substrate, foreground and line tokens form the dark base. Voices are
/// numbered, not named — meaning is performer-assigned at runtime. Semantic
/// tokens (`hot`, `warm`, `cool`, `live`) have fixed meaning and never get
/// reassigned to a voice.
abstract final class PhiColors {
  // region: generated-from-css
  // Auto-generated from `design system/colors_and_type.css`.
  // Run `dart run tool/gen_tokens.dart` to refresh; `--check` to verify drift.

  // ── Substrate ──────────────────────────────────────────────────────────
  static const Color voidField = Color(0xFF06080A);
  static const Color bg0 = Color(0xFF0A0D10);
  static const Color bg1 = Color(0xFF10141A);
  static const Color bg2 = Color(0xFF181D23);
  static const Color bg3 = Color(0xFF21272E);
  static const Color bg4 = Color(0xFF2B3138);

  // ── Foreground ─────────────────────────────────────────────────────────
  static const Color fg0 = Color(0xFFF2F4F6);
  static const Color fg1 = Color(0xFFC1C7CD);
  static const Color fg2 = Color(0xFF7A838D);
  static const Color fg3 = Color(0xFF4A5159);
  static const Color fg4 = Color(0xFF2E343A);

  // ── Borders (rgba on white) ────────────────────────────────────────────
  static const Color line0 = Color(0x0AFFFFFF);
  static const Color line1 = Color(0x14FFFFFF);
  static const Color line2 = Color(0x24FFFFFF);
  static const Color lineHot = Color(0x8CFF3DCB);

  // ── Voices ─────────────────────────────────────────────────────────────
  static const Color voice1 = Color(0xFFFF3DCB);
  static const Color voice2 = Color(0xFF6FD5FF);
  static const Color voice3 = Color(0xFFFFB454);
  static const Color voice4 = Color(0xFFA8FC5C);
  static const Color voice5 = Color(0xFFB58DFF);
  static const Color voice6 = Color(0xFFFFE066);

  // ── Voice glow shells ──────────────────────────────────────────────────
  static const Color voice1Soft = Color(0x52FF3DCB);
  static const Color voice2Soft = Color(0x476FD5FF);
  static const Color voice3Soft = Color(0x47FFB454);
  static const Color voice4Soft = Color(0x47A8FC5C);
  static const Color voice5Soft = Color(0x47B58DFF);
  static const Color voice6Soft = Color(0x47FFE066);

  // ── Semantic ───────────────────────────────────────────────────────────
  static const Color hot = Color(0xFFFF4D4D);
  static const Color warm = Color(0xFFFFB454);
  static const Color cool = Color(0xFF6FD5FF);
  static const Color live = Color(0xFFFF3DCB);

  // ── Annotation ─────────────────────────────────────────────────────────
  static const Color noteBg = Color(0xFF262117);
  static const Color noteFg = Color(0xFFE8DFC0);
  static const Color noteLine = Color(0x2EFFE066);

  // ── Note swatches (dark, then light) ───────────────────────────────────
  static const Color noteAmberBg = Color(0xFF2B2114);
  static const Color noteAmberFg = Color(0xFFF6DFBD);
  static const Color noteAmberLine = Color(0x4DFFB454);
  static const Color noteCyanBg = Color(0xFF13232B);
  static const Color noteCyanFg = Color(0xFFCDEEFB);
  static const Color noteCyanLine = Color(0x476FD5FF);
  static const Color noteGreenBg = Color(0xFF1A2614);
  static const Color noteGreenFg = Color(0xFFDCF5C6);
  static const Color noteGreenLine = Color(0x42A8FC5C);
  static const Color noteVioletBg = Color(0xFF1F1A2C);
  static const Color noteVioletFg = Color(0xFFE2D6FB);
  static const Color noteVioletLine = Color(0x4DB58DFF);
  static const Color noteRoseBg = Color(0xFF2A1624);
  static const Color noteRoseFg = Color(0xFFF7D0EA);
  static const Color noteRoseLine = Color(0x4DFF3DCB);
  static const Color noteSlateBg = Color(0xFF1B2026);
  static const Color noteSlateFg = Color(0xFFDDE2E7);
  static const Color noteSlateLine = Color(0x24FFFFFF);
  static const Color noteAmberBgLight = Color(0xFFFBE9D0);
  static const Color noteAmberFgLight = Color(0xFF3D2A10);
  static const Color noteAmberLineLight = Color(0x59B87014);
  static const Color noteCyanBgLight = Color(0xFFD8F1FB);
  static const Color noteCyanFgLight = Color(0xFF0F3442);
  static const Color noteCyanLineLight = Color(0x591482B4);
  static const Color noteGreenBgLight = Color(0xFFE3F7D0);
  static const Color noteGreenFgLight = Color(0xFF24400E);
  static const Color noteGreenLineLight = Color(0x5950961E);
  static const Color noteVioletBgLight = Color(0xFFEBE2FB);
  static const Color noteVioletFgLight = Color(0xFF2E1D52);
  static const Color noteVioletLineLight = Color(0x596E46C8);
  static const Color noteRoseBgLight = Color(0xFFFBDCF1);
  static const Color noteRoseFgLight = Color(0xFF4D1239);
  static const Color noteRoseLineLight = Color(0x59C81E96);
  static const Color noteSlateBgLight = Color(0xFFE4E8EC);
  static const Color noteSlateFgLight = Color(0xFF20262C);
  static const Color noteSlateLineLight = Color(0x29000000);

  // ── Grid ───────────────────────────────────────────────────────────────
  static const Color grid = Color(0x06FFFFFF);
  static const Color gridStrong = Color(0x0FFFFFFF);
  // endregion: generated-from-css
}
