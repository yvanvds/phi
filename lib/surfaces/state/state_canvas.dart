import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_grid_painter.dart';
import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../domain/state_machine/performance_state_id.dart';
import '../../engine/state/state_machine_controller.dart';
import 'state_ghost_transition.dart';
import 'state_node_view.dart';
import 'state_transition_layer.dart';

/// The state-graph pan/zoom canvas. Hosts the grid backdrop (reused
/// from the patcher — same scope-backdrop intent), the transition layer,
/// every state node, and the in-flight ghost transition. Tracks the
/// cursor's canvas-local position so the ghost can follow it.
class StateCanvas extends StatefulWidget {
  const StateCanvas({required this.controller, super.key});

  final StateMachineController controller;

  @override
  State<StateCanvas> createState() => _StateCanvasState();
}

class _StateCanvasState extends State<StateCanvas> {
  Offset _cursor = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Listener(
      onPointerMove: (e) => _updateCursor(e.localPosition),
      onPointerHover: (e) => _updateCursor(e.localPosition),
      onPointerUp: (e) => _onPointerUp(e.localPosition),
      child: InteractiveViewer(
        transformationController: controller.transform,
        constrained: false,
        minScale: 0.25,
        maxScale: 4.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: SizedBox(
          width: StateCanvasConstants.canvasSize,
          height: StateCanvasConstants.canvasSize,
          child: ListenableBuilder(
            listenable: controller.graph,
            builder: (context, _) {
              final graph = controller.graph;
              final rects = <PerformanceStateId, Rect>{
                for (final s in graph.states) s.id: rectFor(s),
              };
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: PatchGridPainter()),
                    ),
                  ),
                  Positioned.fill(
                    child: StateTransitionLayer(
                      transitions: graph.transitions,
                      nodeRects: rects,
                      version: graph.version,
                    ),
                  ),
                  for (final s in graph.states)
                    Positioned(
                      left: s.position.dx,
                      top: s.position.dy,
                      width: StateCanvasConstants.nodeWidth,
                      height: StateCanvasConstants.nodeHeight,
                      child: StateNodeView(
                        state: s,
                        controller: controller,
                        onPinDown: _onPinDown,
                      ),
                    ),
                  if (graph.dragSourceStateId != null)
                    Positioned.fill(
                      child: StateGhostTransition(
                        source:
                            rects[graph.dragSourceStateId!]?.center ??
                            Offset.zero,
                        cursor: _cursor,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _updateCursor(Offset local) {
    if (widget.controller.graph.dragSourceStateId == null) return;
    setState(() => _cursor = local);
  }

  void _onPinDown(PerformanceStateId from, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    setState(() => _cursor = local);
    widget.controller.beginTransitionDrag(from);
  }

  void _onPointerUp(Offset local) {
    final source = widget.controller.graph.dragSourceStateId;
    if (source == null) return;
    final hit = _findStateAt(local);
    if (hit != null && hit != source) {
      widget.controller.connect(source, hit);
    }
    widget.controller.endTransitionDrag();
  }

  PerformanceStateId? _findStateAt(Offset local) {
    const pad = StateCanvasConstants.nodeHitPadding;
    for (final s in widget.controller.graph.states) {
      final r = rectFor(s).inflate(pad);
      if (r.contains(local)) return s.id;
    }
    return null;
  }
}
