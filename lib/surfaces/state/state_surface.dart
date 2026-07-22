import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/session/session_state.dart';
import '../../engine/engine.dart';
import '../surface.dart';
import 'state_canvas.dart';

/// State graph surface — pan/zoom canvas of performance states and the
/// directed transitions between them, rendered from the registry's `state.`
/// entities through the engine's `StateMachineController` (issue #241).
///
/// Requires the engine to be started: the controller is created in
/// [PhiEngine.start] — which also seeds the default `intro → verse` pair
/// into its own scratch registry when no project is bound — and torn down
/// in `stop`. Before start the surface renders a low-key placeholder.
class StateSurface extends Surface {
  const StateSurface({required this.engine, required this.session, super.key});

  final PhiEngine engine;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final controller = engine.stateMachineOrNull;
    return Container(
      color: PhiColors.bg0,
      child: controller != null
          ? StateCanvas(
              controller: controller,
              session: session,
              variables: engine.runtimeVariablesOrNull,
            )
          : const _Offline(),
    );
  }
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
