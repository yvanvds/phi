import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

import 'phi_colors.dart';

/// One named **note colour** (issue #511): the field, ink and frame a `.text`
/// note is painted with when it is given that swatch, in a dark and a light
/// variant. Source of truth: the `--note-<name>-bg/-fg/-line` triples in
/// `design system/colors_and_type.css` (`:root` for dark, the
/// `:root[data-theme="light"]` block for light), mirrored into [PhiColors].
///
/// A note stores the swatch's [name] — the CSS token stem, e.g.
/// `note-amber` — never a hex, so a theme change carries the note with it.
/// Each pair is a dim field under pale ink in dark and a pale field under dark
/// ink in light, so a coloured note is never dark-on-dark.
///
/// A note with no swatch keeps the plain paper look ([PhiColors.noteBg]); that
/// is not one of [all].
class PhiNoteSwatch {
  const PhiNoteSwatch._({
    required this.name,
    required this.label,
    required this.bgDark,
    required this.fgDark,
    required this.lineDark,
    required this.bgLight,
    required this.fgLight,
    required this.lineLight,
  });

  /// The token name stored in a note's `bg` GUI property (`note-amber`).
  final String name;

  /// The short, human name shown for the swatch (`amber`).
  final String label;

  final Color bgDark;
  final Color fgDark;
  final Color lineDark;
  final Color bgLight;
  final Color fgLight;
  final Color lineLight;

  /// The note field under [brightness].
  Color bg(Brightness brightness) =>
      brightness == Brightness.light ? bgLight : bgDark;

  /// The note ink under [brightness] — paired with [bg] for contrast.
  Color fg(Brightness brightness) =>
      brightness == Brightness.light ? fgLight : fgDark;

  /// The note frame under [brightness].
  Color line(Brightness brightness) =>
      brightness == Brightness.light ? lineLight : lineDark;

  static const PhiNoteSwatch amber = PhiNoteSwatch._(
    name: 'note-amber',
    label: 'amber',
    bgDark: PhiColors.noteAmberBg,
    fgDark: PhiColors.noteAmberFg,
    lineDark: PhiColors.noteAmberLine,
    bgLight: PhiColors.noteAmberBgLight,
    fgLight: PhiColors.noteAmberFgLight,
    lineLight: PhiColors.noteAmberLineLight,
  );

  static const PhiNoteSwatch cyan = PhiNoteSwatch._(
    name: 'note-cyan',
    label: 'cyan',
    bgDark: PhiColors.noteCyanBg,
    fgDark: PhiColors.noteCyanFg,
    lineDark: PhiColors.noteCyanLine,
    bgLight: PhiColors.noteCyanBgLight,
    fgLight: PhiColors.noteCyanFgLight,
    lineLight: PhiColors.noteCyanLineLight,
  );

  static const PhiNoteSwatch green = PhiNoteSwatch._(
    name: 'note-green',
    label: 'green',
    bgDark: PhiColors.noteGreenBg,
    fgDark: PhiColors.noteGreenFg,
    lineDark: PhiColors.noteGreenLine,
    bgLight: PhiColors.noteGreenBgLight,
    fgLight: PhiColors.noteGreenFgLight,
    lineLight: PhiColors.noteGreenLineLight,
  );

  static const PhiNoteSwatch violet = PhiNoteSwatch._(
    name: 'note-violet',
    label: 'violet',
    bgDark: PhiColors.noteVioletBg,
    fgDark: PhiColors.noteVioletFg,
    lineDark: PhiColors.noteVioletLine,
    bgLight: PhiColors.noteVioletBgLight,
    fgLight: PhiColors.noteVioletFgLight,
    lineLight: PhiColors.noteVioletLineLight,
  );

  static const PhiNoteSwatch rose = PhiNoteSwatch._(
    name: 'note-rose',
    label: 'rose',
    bgDark: PhiColors.noteRoseBg,
    fgDark: PhiColors.noteRoseFg,
    lineDark: PhiColors.noteRoseLine,
    bgLight: PhiColors.noteRoseBgLight,
    fgLight: PhiColors.noteRoseFgLight,
    lineLight: PhiColors.noteRoseLineLight,
  );

  static const PhiNoteSwatch slate = PhiNoteSwatch._(
    name: 'note-slate',
    label: 'slate',
    bgDark: PhiColors.noteSlateBg,
    fgDark: PhiColors.noteSlateFg,
    lineDark: PhiColors.noteSlateLine,
    bgLight: PhiColors.noteSlateBgLight,
    fgLight: PhiColors.noteSlateFgLight,
    lineLight: PhiColors.noteSlateLineLight,
  );

  /// Every swatch, in palette order.
  static const List<PhiNoteSwatch> all = [
    amber,
    cyan,
    green,
    violet,
    rose,
    slate,
  ];

  /// The swatch stored as [name], or null for none — an empty value, or a
  /// name this build does not know (the note then keeps the plain look).
  static PhiNoteSwatch? byName(String name) {
    for (final s in all) {
      if (s.name == name) return s;
    }
    return null;
  }
}
