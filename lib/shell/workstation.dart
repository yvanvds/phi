import 'package:flutter/material.dart';

import '../design/tokens/phi_colors.dart';
import '../domain/session/session_state.dart';
import '../engine/engine.dart';
import '../surfaces/mix/mix_surface.dart';
import 'bottom_status/bottom_status.dart';
import 'left_rail/left_rail.dart';
import 'left_rail/surface_id.dart';
import 'right_inspector/right_inspector.dart';
import 'top_toolbar/top_toolbar.dart';

/// Phi workstation chrome — composes the four fixed regions (top toolbar,
/// left rail, right inspector, bottom status) around the active surface in
/// the centre.
class Workstation extends StatefulWidget {
  const Workstation({required this.engine, required this.session, super.key});

  final PhiEngine engine;
  final SessionState session;

  @override
  State<Workstation> createState() => _WorkstationState();
}

class _WorkstationState extends State<Workstation> {
  SurfaceId _selected = SurfaceId.mix;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PhiColors.bg0,
      child: Column(
        children: [
          TopToolbar(session: widget.session),
          Expanded(
            child: Row(
              children: [
                LeftRail(
                  selected: _selected,
                  onSelect: (id) => setState(() => _selected = id),
                ),
                Expanded(child: _buildCentre()),
                RightInspector(engine: widget.engine),
              ],
            ),
          ),
          BottomStatus(engine: widget.engine, session: widget.session),
        ],
      ),
    );
  }

  Widget _buildCentre() {
    switch (_selected) {
      case SurfaceId.mix:
        return MixSurface(engine: widget.engine);
      case SurfaceId.scene:
      case SurfaceId.patcher:
      case SurfaceId.code:
      case SurfaceId.state:
      case SurfaceId.midi:
        return Container(color: PhiColors.bg0);
    }
  }
}
