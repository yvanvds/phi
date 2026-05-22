import 'package:flutter/widgets.dart';

import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../design/widgets/state_machine/state_transition_geometry.dart';
import '../../design/widgets/state_machine/state_transition_painter.dart';
import '../../domain/state_machine/performance_state_id.dart';
import '../../domain/state_machine/state_transition.dart';

/// Wraps the [StateTransitionPainter] in a `GestureDetector` that maps a
/// tap on the canvas onto the nearest transition arrow. The painter
/// itself stays unaware of input — it just draws.
///
/// Hit-testing samples each transition's cubic Bézier and picks the
/// closest one within [StateCanvasConstants.transitionHitThreshold]
/// canvas-local pixels. Misses are silent (no callback) so node drags
/// landing in the gaps between arrows aren't intercepted.
class StateTransitionLayer extends StatelessWidget {
  const StateTransitionLayer({
    required this.transitions,
    required this.nodeRects,
    required this.version,
    this.onTransitionTap,
    super.key,
  });

  final List<StateTransition> transitions;
  final Map<PerformanceStateId, Rect> nodeRects;
  final int version;

  /// Called with the in-graph transition whose arrow was tapped. `null`
  /// to make the layer non-interactive — useful in tests / future
  /// read-only renders.
  final void Function(StateTransition transition)? onTransitionTap;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      painter: StateTransitionPainter(
        transitions: transitions,
        nodeRects: nodeRects,
        version: version,
      ),
      child: const SizedBox.expand(),
    );
    if (onTransitionTap == null) {
      return IgnorePointer(child: paint);
    }
    return GestureDetector(
      // `deferToChild` — the layer only claims a tap when it lands on
      // (or near) a transition. Anywhere else the gesture falls through
      // to whatever is layered below (the canvas pan/zoom, the nodes).
      behavior: HitTestBehavior.deferToChild,
      onTapDown: (d) {
        final hit = _hitTest(d.localPosition);
        if (hit != null) onTransitionTap!(hit);
      },
      child: paint,
    );
  }

  StateTransition? _hitTest(Offset local) {
    StateTransition? best;
    var bestDistance = StateCanvasConstants.transitionHitThreshold;
    for (final t in transitions) {
      final src = nodeRects[t.sourceId];
      final dst = nodeRects[t.targetId];
      if (src == null || dst == null) continue;
      final curve = StateTransitionGeometry.curveBetween(src, dst);
      final d = StateTransitionGeometry.distanceTo(curve, local);
      if (d < bestDistance) {
        bestDistance = d;
        best = t;
      }
    }
    return best;
  }
}
