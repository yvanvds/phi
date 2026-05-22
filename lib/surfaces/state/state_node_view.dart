import 'package:flutter/widgets.dart';

import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../design/widgets/state_machine/state_node_frame.dart';
import '../../domain/state_machine/performance_state.dart';
import '../../domain/state_machine/performance_state_id.dart';
import '../../engine/state/state_machine_controller.dart';

/// Binds one [PerformanceState] to a [StateNodeFrame] and routes pointer
/// drags into `controller.moveState`. Each of the four corner pins claims
/// pointer-downs ahead of the body's pan gesture so the user can
/// drag-author a transition without competing with the node-move gesture.
class StateNodeView extends StatelessWidget {
  const StateNodeView({
    required this.state,
    required this.controller,
    required this.onPinDown,
    super.key,
  });

  final PerformanceState state;
  final StateMachineController controller;

  /// Called when the user presses on one of this node's corner pins. The
  /// canvas uses this to start a drag-to-create-transition gesture.
  final void Function(PerformanceStateId from, Offset globalPosition) onPinDown;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => controller.moveState(state.id, d.delta),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              StateNodeFrame(name: state.name, voice: state.voice),
              for (final corner in _PinCorner.values)
                Positioned(
                  left: corner.isLeft
                      ? -StateCanvasConstants.pinHitRadius / 2
                      : null,
                  right: corner.isLeft
                      ? null
                      : -StateCanvasConstants.pinHitRadius / 2,
                  top: corner.isTop
                      ? -StateCanvasConstants.pinHitRadius / 2
                      : null,
                  bottom: corner.isTop
                      ? null
                      : -StateCanvasConstants.pinHitRadius / 2,
                  width: StateCanvasConstants.pinHitRadius,
                  height: StateCanvasConstants.pinHitRadius,
                  // Invisible hit-target overlaying the frame's pin dot —
                  // claims pointer-downs to start a transition drag
                  // without double-drawing the visible dot.
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) => onPinDown(state.id, e.position),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _PinCorner {
  topLeft(isLeft: true, isTop: true),
  topRight(isLeft: false, isTop: true),
  bottomLeft(isLeft: true, isTop: false),
  bottomRight(isLeft: false, isTop: false);

  const _PinCorner({required this.isLeft, required this.isTop});

  final bool isLeft;
  final bool isTop;
}

/// Compute the canvas-local rectangle for a state node — used by the
/// canvas to build the `Map<PerformanceStateId, Rect>` the transition
/// painter consumes.
Rect rectFor(PerformanceState state) {
  return Rect.fromLTWH(
    state.position.dx,
    state.position.dy,
    StateCanvasConstants.nodeWidth,
    StateCanvasConstants.nodeHeight,
  );
}
