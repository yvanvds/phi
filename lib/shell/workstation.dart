import 'package:flutter/material.dart';

import '../design/tokens/phi_colors.dart';
import '../domain/session/session_state.dart';
import '../engine/bridge/no_op_code_evaluator.dart';
import '../engine/engine.dart';
import '../surfaces/code/code_surface.dart';
import '../surfaces/midi/midi_surface.dart';
import '../surfaces/mix/mix_surface.dart';
import '../surfaces/patcher/patcher_surface.dart';
import '../surfaces/scene/scene_surface.dart';
import '../surfaces/state/state_surface.dart';
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
  final NoOpCodeEvaluator _codeEvaluator = NoOpCodeEvaluator();

  @override
  void dispose() {
    _codeEvaluator.dispose();
    super.dispose();
  }

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
    // All surfaces stay in the element tree; IndexedStack only paints the
    // selected one. macbear's `M3AppEngine` is a process-wide singleton
    // that `M3View.dispose` tears down irreversibly, so unmounting the
    // Scene surface crashes any subsequent re-entry.
    return IndexedStack(
      index: SurfaceId.values.indexOf(_selected),
      sizing: StackFit.expand,
      children: [for (final id in SurfaceId.values) _surfaceFor(id)],
    );
  }

  Widget _surfaceFor(SurfaceId id) {
    switch (id) {
      case SurfaceId.scene:
        return SceneSurface(engine: widget.engine);
      case SurfaceId.mix:
        return MixSurface(engine: widget.engine);
      case SurfaceId.patcher:
        return PatcherSurface(engine: widget.engine);
      case SurfaceId.code:
        return CodeSurface(
          engine: widget.engine,
          session: widget.session,
          evaluator: _codeEvaluator,
        );
      case SurfaceId.midi:
        return MidiSurface(engine: widget.engine);
      case SurfaceId.state:
        return StateSurface(engine: widget.engine);
    }
  }
}
