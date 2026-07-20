import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import 'rail_button.dart';
import 'surface_id.dart';

/// Left rail — 48px wide column of icon-only surface buttons. Since the
/// workstation refactor the rail is **identity + summon** (design
/// `docs/design/shell-layout.md` §2): a tap focuses the surface wherever it is
/// docked, or opens it in the active pane if closed. [selected] highlights the
/// focused surface — null when the focused pane is empty, so nothing lights.
/// Only the surfaces that ship with a working stub are enabled.
class LeftRail extends StatelessWidget {
  const LeftRail({required this.selected, required this.onSelect, super.key});

  final SurfaceId? selected;
  final ValueChanged<SurfaceId> onSelect;

  static const Map<SurfaceId, String> _glyphs = {
    SurfaceId.scene: '◌',
    SurfaceId.patcher: '⌬',
    SurfaceId.code: '⌨',
    SurfaceId.state: '⊞',
    SurfaceId.midi: '♪',
    SurfaceId.racks: '▤',
    SurfaceId.mix: '≡',
  };

  static const Set<SurfaceId> _enabled = {
    SurfaceId.scene,
    SurfaceId.patcher,
    SurfaceId.code,
    SurfaceId.state,
    SurfaceId.midi,
    SurfaceId.racks,
    SurfaceId.mix,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PhiSpacing.leftRailWidth,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(right: BorderSide(color: PhiColors.line1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: PhiSpacing.s2),
      child: Column(
        children: [
          for (final id in SurfaceId.values)
            SizedBox(
              height: 40,
              width: double.infinity,
              child: RailButton(
                glyph: _glyphs[id] ?? '·',
                label: id.label,
                selected: id == selected,
                enabled: _enabled.contains(id),
                onPressed: () => onSelect(id),
              ),
            ),
        ],
      ),
    );
  }
}
