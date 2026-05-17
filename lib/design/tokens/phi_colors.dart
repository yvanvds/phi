import 'package:flutter/painting.dart';

/// Phi colour tokens. Source of truth: `design system/colors_and_type.css`.
///
/// Substrate, foreground and line tokens form the dark base. Voices are
/// numbered, not named — meaning is performer-assigned at runtime. Semantic
/// tokens (`hot`, `warm`, `cool`, `live`) have fixed meaning and never get
/// reassigned to a voice.
abstract final class PhiColors {
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

  // ── Grid ───────────────────────────────────────────────────────────────
  static const Color grid = Color(0x06FFFFFF);
  static const Color gridStrong = Color(0x0FFFFFFF);
}
