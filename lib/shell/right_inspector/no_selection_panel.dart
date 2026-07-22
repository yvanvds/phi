import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';

/// The right inspector's empty context panel — shown when nothing is
/// selected on any surface, and when a stale selection points at an entity
/// that no longer exists (deleted, or renamed from elsewhere).
class NoSelectionPanel extends StatelessWidget {
  const NoSelectionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NO SELECTION', style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s2),
        Text(
          'Select an object on a surface to edit its properties here.',
          style: PhiType.small(),
        ),
      ],
    );
  }
}
