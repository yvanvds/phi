import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';
import '../../tokens/phi_motion.dart';
import '../../tokens/phi_radii.dart';
import '../../tokens/phi_type.dart';

/// Phi primary button. Fuchsia border + glow when armed; uppercase mono label.
///
/// The button has two states: idle (default substrate) and armed
/// (`isArmed: true`) where the border lights up `lineHot` and a soft fuchsia
/// glow surrounds it.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isArmed = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isArmed;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  Color get _background {
    if (_pressed) return PhiColors.bg3;
    if (_hovered) return PhiColors.bg2;
    return PhiColors.bg1;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: PhiMotion.dur2,
          curve: PhiMotion.easeOut,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _background,
            borderRadius: PhiRadii.all2,
            border: Border.all(
              color: widget.isArmed ? PhiColors.lineHot : PhiColors.line1,
            ),
            boxShadow: widget.isArmed
                ? const [BoxShadow(color: PhiColors.voice1Soft, blurRadius: 12)]
                : null,
          ),
          child: Center(
            child: Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: Text(
                widget.label.toUpperCase(),
                style: PhiType.caption().copyWith(
                  color: widget.isArmed ? PhiColors.voice1 : PhiColors.fg0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
