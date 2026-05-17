import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';

/// Phi capsule (tag / badge). 22px pill with a glowing voice-colored dot and
/// uppercased mono label.
///
/// Defaults to fuchsia ([PhiColors.voice1]) — the canonical "live" voice.
/// Pass a different [color] to mark a different voice or a semantic state.
class Capsule extends StatelessWidget {
  const Capsule({
    required this.label,
    this.color = PhiColors.voice1,
    this.showDot = true,
    super.key,
  });

  final String label;
  final Color color;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.allPill,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: PhiType.mono().copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.08 * 10,
            ),
          ),
        ],
      ),
    );
  }
}
