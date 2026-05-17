import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// Top toolbar — 36px strip. Phase 1 shows the wordmark and an idle
/// transport region; the rest comes online as features land.
class TopToolbar extends StatelessWidget {
  const TopToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PhiSpacing.topToolbarHeight,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s4),
      child: Row(
        children: [
          Text(
            'phi',
            style: PhiType.h2().copyWith(
              color: PhiColors.voice1,
              shadows: const [
                Shadow(color: PhiColors.voice1Soft, blurRadius: 12),
              ],
            ),
          ),
          const SizedBox(width: PhiSpacing.s4),
          Text('workstation', style: PhiType.caption()),
          const Spacer(),
          Text('phase 1 · hello world', style: PhiType.caption()),
        ],
      ),
    );
  }
}
