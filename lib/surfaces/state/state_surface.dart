import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../engine/engine.dart';
import '../../engine/state/state_machine_controller.dart';
import '../surface.dart';
import 'state_canvas.dart';

/// State graph surface — pan/zoom canvas of performance states and the
/// directed transitions between them.
///
/// Requires the engine to be started: the [StateMachineController] is
/// created in [PhiEngine.start] and torn down in `stop`. Before start the
/// surface renders a low-key placeholder.
class StateSurface extends Surface {
  const StateSurface({required this.engine, super.key});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: engine.stateMachineOrNull != null
          ? _StateViewport(engine: engine)
          : const _Offline(),
    );
  }
}

/// Inner widget that owns the one-shot seeding of the default graph.
///
/// Kept separate so the seed runs once on first mount, not on every
/// Flutter rebuild of the surrounding chrome.
class _StateViewport extends StatefulWidget {
  const _StateViewport({required this.engine});

  final PhiEngine engine;

  @override
  State<_StateViewport> createState() => _StateViewportState();
}

class _StateViewportState extends State<_StateViewport> {
  @override
  void initState() {
    super.initState();
    _seedDefaultGraphIfEmpty(widget.engine.stateMachine);
  }

  void _seedDefaultGraphIfEmpty(StateMachineController controller) {
    if (controller.graph.states.isNotEmpty) return;
    final intro = controller.addState(
      name: 'intro',
      position: const Offset(160, 160),
      voice: 1,
    );
    final verse = controller.addState(
      name: 'verse',
      position: const Offset(400, 160),
      voice: 2,
    );
    controller.connect(intro.id, verse.id);
    // Seed an active state so first-open shows the LIVE chrome — without
    // this the demo graph looks identical to the pre-#41 scaffold and
    // the new arming UX has nothing to react against.
    controller.setActive(intro.id);
  }

  @override
  Widget build(BuildContext context) =>
      StateCanvas(controller: widget.engine.stateMachine);
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'state offline · start the engine'.toUpperCase(),
        style: PhiType.caption(),
      ),
    );
  }
}
