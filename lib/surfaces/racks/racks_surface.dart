import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/synth/fm_bank_reader.dart';
import '../../engine/state/rack_definitions_controller.dart';
import '../../engine/state/voice_audition_controller.dart';
import '../surface.dart';
import 'definition_editor_pane.dart';
import 'definitions_panel.dart';
import 'rack_asset_source.dart';
import 'voices_pane.dart';

/// The **Racks** surface (issue #209, design `docs/design/racks-and-voices.md`
/// §8) — the three-pane home for synth / fx definitions and playable voices:
///
/// - **left** — [DefinitionsPanel]: the `synth.` and `fx.` trees with the full
///   registry affordances (per-kind add, group, reorder, duplicate, rename,
///   delete-with-impact).
/// - **center** — [DefinitionEditorPane]: the selected definition's editor
///   (a routed placeholder here; per-kind panels land in #212).
/// - **right** — [VoicesPane]: one editable row per `voice.` (bind / colour /
///   kind, arm-for-input, and the audition test strip; issue #211).
///
/// It binds to the shell-owned [RackDefinitionsController]. That is `null` only
/// in the bare Phase-1 tests that wire no project; the surface then shows a hint
/// so the rail entry still renders.
///
/// The center editor's per-kind panels (issue #210) reach two injected seams:
/// [assetSource] imports `.syx` / `.sfz` / sample files into the project's
/// `assets/` folder, and [bankReader] browses an FM bank's patch names. Both are
/// optional — the panels degrade gracefully when a bare test leaves them null.
class RacksSurface extends Surface {
  const RacksSurface({
    required this.controller,
    this.audition,
    this.assetSource,
    this.bankReader,
    super.key,
  });

  final RackDefinitionsController? controller;

  /// Arm-for-input + audition seam driving the voices pane (issue #211). `null`
  /// in the bare Phase-1 tests / projects with no MIDI subsystem — the voices
  /// pane then disables arming and the test strip but still edits rows.
  final VoiceAuditionController? audition;

  final RackAssetSource? assetSource;
  final FmBankReader? bankReader;

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
          Expanded(
            child: DefinitionEditorPane(
              controller: controller,
              assetSource: assetSource,
              bankReader: bankReader,
            ),
          ),
          VoicesPane(controller: controller, audition: audition),
        ],
      ),
    );
  }
}
