import 'package:flutter/material.dart';

import 'tokens/phi_colors.dart';
import 'tokens/phi_type.dart';

/// Builds a `ThemeData` from the Phi tokens. Material is used as a base, but
/// Phi widgets generally style themselves from the token classes directly.
ThemeData buildPhiTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: PhiColors.bg0,
    canvasColor: PhiColors.bg0,
    colorScheme: const ColorScheme.dark(
      surface: PhiColors.bg0,
      onSurface: PhiColors.fg0,
      primary: PhiColors.voice1,
      onPrimary: PhiColors.voidField,
      secondary: PhiColors.voice2,
      onSecondary: PhiColors.voidField,
      error: PhiColors.hot,
      onError: PhiColors.fg0,
    ),
    textTheme: base.textTheme.copyWith(
      displayLarge: PhiType.displayL(),
      displayMedium: PhiType.displayM(),
      headlineLarge: PhiType.h1(),
      headlineMedium: PhiType.h2(),
      headlineSmall: PhiType.h3(),
      bodyLarge: PhiType.body(),
      bodyMedium: PhiType.body(),
      bodySmall: PhiType.small(),
      labelSmall: PhiType.caption(),
    ),
  );
}
