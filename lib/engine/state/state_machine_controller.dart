import 'package:flutter/widgets.dart';

import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../domain/state_machine/performance_state.dart';
import '../../domain/state_machine/performance_state_id.dart';
import '../../domain/state_machine/state_graph.dart';
import '../../domain/state_machine/state_transition.dart';

/// Engine-side mediator between user gestures and the [StateGraph].
///
/// Owns the Dart-side graph and the [TransformationController] for pan/zoom.
/// Pure Dart for now — the state machine has no native counterpart in
/// `package:yse`, so there is no gateway to mediate against.
class StateMachineController {
  StateMachineController();

  /// The Dart-side graph. Listen for add/remove/transition changes.
  final StateGraph graph = StateGraph();

  /// Pan/zoom state for the [InteractiveViewer] in the canvas.
  final TransformationController transform = TransformationController();

  // ─── state lifecycle ───────────────────────────────────────────────────

  /// Create a state at [position] and add it to the graph. [position] is
  /// snapped to the 16px grid so seeds and drags share one source of truth.
  PerformanceState addState({
    required String name,
    required Offset position,
    int voice = 1,
  }) {
    final state = PerformanceState(
      id: PerformanceStateId.next(),
      name: name,
      voice: voice,
      position: _snap(position),
    );
    graph.addState(state);
    return state;
  }

  /// Remove a state and any transitions touching it.
  void removeState(PerformanceStateId id) => graph.removeState(id);

  /// Move a state by [delta] (canvas-local pixels). The next position is
  /// snapped to the 16px grid — the node "jumps" between grid cells rather
  /// than sliding smoothly, matching the dot grid backdrop.
  void moveState(PerformanceStateId id, Offset delta) {
    final s = graph.stateById(id);
    if (s == null) return;
    s.moveTo(_snap(s.position + delta));
  }

  // ─── transition lifecycle ──────────────────────────────────────────────

  void beginTransitionDrag(PerformanceStateId from) =>
      graph.beginTransitionDrag(from);

  void endTransitionDrag() => graph.endTransitionDrag();

  /// Connect [source] → [target]. Rejects self-loops, duplicates, and
  /// unknown ids. Returns whether the transition was made.
  bool connect(PerformanceStateId source, PerformanceStateId target) {
    if (graph.stateById(source) == null) return false;
    if (graph.stateById(target) == null) return false;
    return graph.addTransition(
      StateTransition(sourceId: source, targetId: target),
    );
  }

  /// Remove [source] → [target]. No-op if no such transition exists.
  void disconnect(PerformanceStateId source, PerformanceStateId target) {
    graph.removeTransition(StateTransition(sourceId: source, targetId: target));
  }

  void dispose() {
    transform.dispose();
    graph.dispose();
  }

  static Offset _snap(Offset p) {
    const step = StateCanvasConstants.snapStep;
    return Offset(
      (p.dx / step).roundToDouble() * step,
      (p.dy / step).roundToDouble() * step,
    );
  }
}
