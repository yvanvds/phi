import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import 'rail_button.dart';
import 'surface_id.dart';

/// Left rail — 48px wide column of icon-only surface buttons. Only the
/// surfaces that ship with a working stub are enabled; the rest stay
/// dimmed until their respective issues land.
class LeftRail extends StatelessWidget {
  const LeftRail({required this.selected, required this.onSelect, super.key});

  final SurfaceId selected;
  final ValueChanged<SurfaceId> onSelect;

  static const Map<SurfaceId, String> _glyphs = {
    SurfaceId.scene: '◌',
    SurfaceId.patcher: '⌬',
    SurfaceId.code: '⌨',
    SurfaceId.state: '⊞',
    SurfaceId.midi: '♪',
    SurfaceId.mix: '≡',
  };

  static const Set<SurfaceId> _enabled = {
    SurfaceId.scene,
    SurfaceId.patcher,
    SurfaceId.code,
    SurfaceId.midi,
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
