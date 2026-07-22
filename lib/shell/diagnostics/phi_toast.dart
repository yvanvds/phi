import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/log/log_level.dart';

/// A single transient toast (design `docs/design/diagnostics.md` §3): a compact
/// card with a severity-tinted accent bar and the notice text. Purely
/// presentational — the overlay owns its lifecycle.
class PhiToast extends StatelessWidget {
  /// Renders [text] with an accent chosen from [level].
  const PhiToast({required this.text, required this.level, super.key});

  /// The notice line.
  final String text;

  /// The severity, driving the accent colour.
  final LogLevel level;

  Color get _accent {
    switch (level) {
      case LogLevel.error:
        return PhiColors.hot;
      case LogLevel.warning:
        return PhiColors.warm;
      case LogLevel.info:
      case LogLevel.debug:
        return PhiColors.cool;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      margin: const EdgeInsets.only(top: PhiSpacing.s2),
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s4,
        vertical: PhiSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all3,
        border: Border.all(color: PhiColors.line2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 26,
            margin: const EdgeInsets.only(right: PhiSpacing.s3),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: PhiRadii.allPill,
            ),
          ),
          Flexible(child: Text(text, style: PhiType.small())),
        ],
      ),
    );
  }
}
