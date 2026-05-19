import 'package:flutter/widgets.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `~sine` node — a single `freq <value>` readout row.
/// Inert in the first PR: the value is driven by an incoming cable from
/// a `.slider` (or by a future tap-to-edit interaction).
class SineNodeBody extends StatelessWidget {
  const SineNodeBody({required this.node, required this.controller, super.key});

  final PatchNode node;
  final PatcherController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('freq', style: PhiType.monoS().copyWith(color: PhiColors.fg2)),
        Text('440', style: PhiType.monoS().copyWith(color: PhiColors.fg0)),
      ],
    );
  }
}
