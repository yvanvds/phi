import 'package:flutter/widgets.dart';

import '../../design/widgets/state_machine/state_transition_painter.dart';
import '../../domain/state_machine/performance_state_id.dart';
import '../../domain/state_machine/state_transition.dart';

/// Thin wrapper around [StateTransitionPainter] — pulled into its own
/// widget so the canvas can lay it out as a fullscreen `Positioned.fill`
/// without leaking painter wiring into [StateCanvas].
class StateTransitionLayer extends StatelessWidget {
  const StateTransitionLayer({
    required this.transitions,
    required this.nodeRects,
    required this.version,
    super.key,
  });

  final List<StateTransition> transitions;
  final Map<PerformanceStateId, Rect> nodeRects;
  final int version;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: StateTransitionPainter(
          transitions: transitions,
          nodeRects: nodeRects,
          version: version,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
