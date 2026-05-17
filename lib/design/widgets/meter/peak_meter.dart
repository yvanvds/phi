import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_motion.dart';
import '../../tokens/phi_radii.dart';

/// Vertical peak meter painted in the YSE convention: phosphor-green at low
/// levels, amber in the middle, red near clipping. The convention overrides
/// any voice-color assignment for the channel — peak meters are universal.
///
/// [level] is a normalised value in `[0, 1]`. 0 → fully dark; 1 → fully lit.
class PeakMeter extends StatelessWidget {
  const PeakMeter({
    required this.level,
    this.width = 8,
    this.height = 64,
    super.key,
  });

  final double level;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = level.clamp(0.0, 1.0);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        borderRadius: PhiRadii.all1,
        border: Border.all(color: PhiColors.line1),
      ),
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: PhiRadii.all1,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            const SizedBox.expand(),
            AnimatedContainer(
              duration: PhiMotion.dur1,
              curve: PhiMotion.easeOut,
              height: (height - 2) * clamped,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [PhiColors.voice4, PhiColors.voice3, PhiColors.hot],
                  stops: [0.0, 0.7, 1.0],
                ),
                boxShadow: clamped > 0.05
                    ? [BoxShadow(color: _glowColor(clamped), blurRadius: 6)]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _glowColor(double level) {
    if (level > 0.9) return PhiColors.hot.withValues(alpha: 0.4);
    if (level > 0.7) return PhiColors.voice3.withValues(alpha: 0.4);
    return PhiColors.voice4.withValues(alpha: 0.3);
  }
}
