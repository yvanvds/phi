import 'package:flutter/painting.dart';

import 'phi_colors.dart';

/// Voice index → colour lookup. Voices are 1-indexed in the design system;
/// out-of-range indices wrap into `[1, 6]` so callers never have to clamp.
abstract final class PhiVoices {
  static const List<Color> _core = [
    PhiColors.voice1,
    PhiColors.voice2,
    PhiColors.voice3,
    PhiColors.voice4,
    PhiColors.voice5,
    PhiColors.voice6,
  ];

  static const List<Color> _soft = [
    PhiColors.voice1Soft,
    PhiColors.voice2Soft,
    PhiColors.voice3Soft,
    PhiColors.voice4Soft,
    PhiColors.voice5Soft,
    PhiColors.voice6Soft,
  ];

  /// Saturated core colour for [voice] in `[1, 6]`.
  static Color color(int voice) => _core[_slot(voice)];

  /// Soft halo colour for [voice] in `[1, 6]`.
  static Color glow(int voice) => _soft[_slot(voice)];

  /// Resolves a voice colour *token* (`voice1..voice6`) to its swatch, defaulting
  /// to the first swatch for any other or opaque token. The domain stores the
  /// token name (a `VoiceDefinition`'s `color`); the design layer paints it.
  static Color colorForToken(String token) {
    const prefix = 'voice';
    if (token.startsWith(prefix)) {
      final index = int.tryParse(token.substring(prefix.length));
      if (index != null) return color(index);
    }
    return color(1);
  }

  static int _slot(int voice) => ((voice - 1) % 6 + 6) % 6;
}
