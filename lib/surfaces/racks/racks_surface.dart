import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../engine/state/rack_definitions_controller.dart';
import '../surface.dart';
import 'definition_editor_pane.dart';
import 'definitions_panel.dart';
import 'voices_pane.dart';

/// The **Racks** surface (issue #209, design `docs/design/racks-and-voices.md`
/// §8) — the three-pane home for synth / fx definitions and playable voices:
///
/// - **left** — [DefinitionsPanel]: the `synth.` and `fx.` trees with the full
///   registry affordances (per-kind add, group, reorder, duplicate, rename,
///   delete-with-impact).
/// - **center** — [DefinitionEditorPane]: the selected definition's editor
///   (a routed placeholder here; per-kind panels land in #212).
/// - **right** — [VoicesPane]: one row per `voice.` (a scaffold here; binding /
///   colour / kind editing + audition land in #211).
///
/// It binds to the shell-owned [RackDefinitionsController]. That is `null` only
/// in the bare Phase-1 tests that wire no project; the surface then shows a hint
/// so the rail entry still renders.
class RacksSurface extends Surface {
  const RacksSurface({required this.controller, super.key});

  final RackDefinitionsController? controller;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) {
      return const ColoredBox(
        color: PhiColors.bg0,
        child: Center(
          child: Text(
            'no project loaded',
            style: TextStyle(color: PhiColors.fg3),
          ),
        ),
      );
    }
    return ColoredBox(
      color: PhiColors.bg0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefinitionsPanel(controller: controller),
          Expanded(child: DefinitionEditorPane(controller: controller)),
          VoicesPane(controller: controller),
        ],
      ),
    );
  }
}
