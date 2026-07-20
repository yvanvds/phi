import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/toggle/phi_toggle.dart';

/// A labelled on/off row built on the design system's [PhiToggle] — the discrete
/// boolean control the FM operator grid (enable) is built from (design
/// `docs/design/racks-and-voices.md` §8).
///
/// Toggling commits immediately through [onChanged] as one journaled edit.
class EditorToggleRow extends StatelessWidget {
  const EditorToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
            ),
          ),
          PhiToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
