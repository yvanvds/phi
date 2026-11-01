import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';

/// A word in a thin box — the patcher's small text button, as the placement
/// bar's edit / run indicator draws it (issue #378). Used by the tutorial
/// banner, the reference panel's "Open tutorial" and the palette tabs
/// (issue #489).
class PatchWordButton extends StatelessWidget {
  const PatchWordButton({
    required this.label,
    required this.onTap,
    this.color = PhiColors.fg1,
    this.selected = false,
    this.tooltip,
    super.key,
  });

  /// The word shown (rendered upper-case, like every patcher caption).
  final String label;

  /// Called on a tap.
  final VoidCallback onTap;

  /// Text and border colour.
  final Color color;

  /// Draws the box filled — a selected tab.
  final bool selected;

  /// Optional hover help.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s1,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: selected ? PhiColors.bg3 : null,
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PhiType.caption().copyWith(color: color),
          ),
        ),
      ),
    );
    final help = tooltip;
    return help == null ? button : Tooltip(message: help, child: button);
  }
}
