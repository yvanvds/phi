import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// A key chord rendered as a small mono keycap, e.g. `Ctrl+E` — shared by the
/// command palette's rows and the keyboard shortcuts overlay (issue #487).
class ShortcutChip extends StatelessWidget {
  const ShortcutChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s2,
        vertical: PhiSpacing.s0,
      ),
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        borderRadius: PhiRadii.all2,
        border: Border.all(color: PhiColors.line1),
      ),
      child: Text(label, style: PhiType.monoS().copyWith(color: PhiColors.fg2)),
    );
  }
}
