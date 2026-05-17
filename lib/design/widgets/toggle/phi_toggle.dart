import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_motion.dart';
import '../../tokens/phi_radii.dart';

/// Phi-themed binary toggle. 38×18 pill with a 12px thumb that animates
/// between left (off) and right (on). Armed state glows fuchsia.
class PhiToggle extends StatelessWidget {
  const PhiToggle({required this.value, required this.onChanged, super.key});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: PhiMotion.dur2,
          curve: PhiMotion.easeOut,
          width: 38,
          height: 18,
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            borderRadius: PhiRadii.allPill,
            border: Border.all(
              color: value ? PhiColors.lineHot : PhiColors.line1,
            ),
            boxShadow: value
                ? const [BoxShadow(color: PhiColors.voice1Soft, blurRadius: 10)]
                : null,
          ),
          padding: const EdgeInsets.all(2),
          child: AnimatedAlign(
            duration: PhiMotion.dur2,
            curve: PhiMotion.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: value ? PhiColors.voice1 : PhiColors.fg2,
                shape: BoxShape.circle,
                boxShadow: value
                    ? const [
                        BoxShadow(color: PhiColors.voice1Soft, blurRadius: 6),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
