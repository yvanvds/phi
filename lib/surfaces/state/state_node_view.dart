import 'package:flutter/widgets.dart';

import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../design/widgets/state_machine/state_node_frame.dart';
import '../../domain/state_machine/performance_state.dart';
import '../../domain/state_machine/performance_state_id.dart';
import '../../domain/state_machine/state_transition.dart';
import '../../engine/state/state_machine_controller.dart';

/// Binds one [PerformanceState] to a [StateNodeFrame] and routes pointer
/// drags into `controller.moveState`. Each of the four corner pins claims
/// pointer-downs ahead of the body's pan gesture so the user can
/// drag-author a transition without competing with the node-move gesture.
///
/// When [armedTransition] is non-null the node renders the amber
/// "armed" capsule and a tap on the frame's body fires that transition.
/// When [isLive] is true the node renders the fuchsia "● LIVE" capsule.
/// When [selected] is true an outer fuchsia ring is drawn around the
/// node — composed with the inner mode so a live or armed node can also
/// carry the selection ring. Tapping always publishes [onSelect]; if the
/// node also carries an armed transition the tap fires it after
/// selecting. Pan still wins over tap if the pointer moves — pan
/// recognisers beat tap recognisers in Flutter's gesture arena once the
/// slop threshold is crossed.
class StateNodeView extends StatelessWidget {
  const StateNodeView({
    required this.state,
    required this.controller,
    required this.onPinDown,
    required this.onSelect,
    this.isLive = false,
    this.armedTransition,
    this.selected = false,
    super.key,
  });

  final PerformanceState state;
  final StateMachineController controller;

  /// Called when the user presses on one of this node's corner pins. The
  /// canvas uses this to start a drag-to-create-transition gesture.
  final void Function(PerformanceStateId from, Offset globalPosition) onPinDown;

  /// Called on tap so the surface can publish [state] as the
  /// cross-surface selection.
  final VoidCallback onSelect;

  /// Whether this node is the graph's current active state.
  final bool isLive;

  /// The armed transition targeting this node, if any. Drives the
  /// `▲ ARMED · {fireOn}` capsule and the tap-to-fire gesture.
  final StateTransition? armedTransition;

  /// Whether this node carries the cross-surface selection. Drives the
  /// outer fuchsia ring on the frame.
  final bool selected;

  StateNodeDisplay get _display {
    if (isLive) return StateNodeDisplay.live;
    if (armedTransition != null) return StateNodeDisplay.armed;
    return StateNodeDisplay.idle;
  }

  void _onTap() {
    onSelect();
    final armed = armedTransition;
    if (armed != null) controller.fire(armed);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => controller.moveState(state.id, d.delta),
          onTap: _onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              StateNodeFrame(
                name: state.name,
                voice: state.voice,
                display: _display,
                armedLabel: armedTransition?.fireOn,
                selected: selected,
              ),
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
