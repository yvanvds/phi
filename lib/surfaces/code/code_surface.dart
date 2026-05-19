import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/session/session_state.dart';
import '../../engine/bridge/code_evaluator.dart';
import '../../engine/engine.dart';
import '../surface.dart';
import 'code_editor_view.dart';
import 'code_eval_flash.dart';
import 'code_projected_view.dart';
import 'code_seed.dart';

/// Live coding surface — Python editor with a working view (re_editor)
/// and a projected view (read-only, comments stripped). Ctrl+Enter
/// evaluates the block under the cursor through [evaluator]; the
/// scaffold ships with a [NoOpCodeEvaluator] default until the real
/// kernel path is decided.
///
/// The working/projected switch listens to [SessionState.projection],
/// so the top toolbar's projection toggle drives both this surface and
/// the rest of the workstation in lock-step.
class CodeSurface extends Surface {
  const CodeSurface({
    required this.engine,
    required this.session,
    required this.evaluator,
    String? seedSource,
    super.key,
  }) : _seedSource = seedSource;

  final PhiEngine engine;
  final SessionState session;
  final CodeEvaluator evaluator;
  final String? _seedSource;

  @override
  Widget build(BuildContext context) {
    return _CodeViewport(
      session: session,
      evaluator: evaluator,
      seedSource: _seedSource ?? codeSurfaceSeed,
    );
  }
}

class _CodeViewport extends StatefulWidget {
  const _CodeViewport({
    required this.session,
    required this.evaluator,
    required this.seedSource,
  });

  final SessionState session;
  final CodeEvaluator evaluator;
  final String seedSource;

  @override
  State<_CodeViewport> createState() => _CodeViewportState();
}

class _CodeViewportState extends State<_CodeViewport> {
  late final CodeLineEditingController _controller;
  late final CodeEvalFlash _flash;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.seedSource);
    _flash = CodeEvalFlash();
  }

  @override
  void dispose() {
    _flash.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.session.projection,
        builder: (context, projected, _) {
          if (projected) {
            return CodeProjectedView(controller: _controller, flash: _flash);
          }
          return CodeEditorView(
            controller: _controller,
            evaluator: widget.evaluator,
            flash: _flash,
          );
        },
      ),
    );
  }
}
