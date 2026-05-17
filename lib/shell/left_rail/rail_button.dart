import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';

/// Square icon-only button used in the left rail. Phase 1 uses a single-glyph
/// label until the bespoke surface glyphs land.
class RailButton extends StatefulWidget {
  const RailButton({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final String glyph;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<RailButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.selected;
    final bg = highlight
        ? PhiColors.bg2
        : (_hovered ? PhiColors.bg2 : PhiColors.bg1);
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: PhiMotion.dur2,
            curve: PhiMotion.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: PhiRadii.all2,
              border: Border.all(
                color: highlight ? PhiColors.lineHot : PhiColors.line0,
              ),
              boxShadow: highlight
                  ? const [
                      BoxShadow(color: PhiColors.voice1Soft, blurRadius: 10),
                    ]
                  : null,
            ),
            child: Center(
              child: Opacity(
                opacity: widget.enabled ? 1.0 : 0.35,
                child: Text(
                  widget.glyph,
                  style: PhiType.mono().copyWith(
                    color: highlight ? PhiColors.voice1 : PhiColors.fg1,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
