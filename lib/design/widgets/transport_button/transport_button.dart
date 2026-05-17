import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_motion.dart';
import '../../tokens/phi_radii.dart';

/// 28×28 square icon button used in the top toolbar's transport region.
/// Armed state lights fuchsia border + glow.
class TransportButton extends StatefulWidget {
  const TransportButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isActive = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isActive;

  @override
  State<TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<TransportButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered ? PhiColors.bg2 : PhiColors.bg1;
    final fg = widget.isActive ? PhiColors.voice1 : PhiColors.fg1;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: PhiMotion.dur2,
            curve: PhiMotion.easeOut,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: PhiRadii.all2,
              border: Border.all(
                color: widget.isActive ? PhiColors.lineHot : PhiColors.line1,
              ),
              boxShadow: widget.isActive
                  ? const [
                      BoxShadow(color: PhiColors.voice1Soft, blurRadius: 10),
                    ]
                  : null,
            ),
            child: Icon(widget.icon, size: 14, color: fg),
          ),
        ),
      ),
    );
  }
}
