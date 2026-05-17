import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// Right inspector — collapsed in Phase 1. A 28px-wide strip with a rotated
/// label as the hint that there's content to expand later.
class RightInspector extends StatelessWidget {
  const RightInspector({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PhiSpacing.rightInspectorCollapsedWidth,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(left: BorderSide(color: PhiColors.line1)),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text('INSPECTOR', style: PhiType.caption()),
        ),
      ),
    );
  }
}
