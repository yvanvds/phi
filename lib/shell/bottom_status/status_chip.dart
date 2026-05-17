import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// Two-segment status capsule shown in the bottom strip: a small mono label
/// ("CPU", "DROPS") followed by a glowing readout value.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: PhiType.caption().copyWith(color: PhiColors.fg3)),
          const SizedBox(width: PhiSpacing.s2),
          Text(value, style: PhiType.readout()),
        ],
      ),
    );
  }
}
