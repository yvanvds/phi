import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/code/python_traceback.dart';
import '../../domain/session/session_state.dart';
import '../../engine/bridge/code_evaluator.dart';
import '../../engine/engine.dart';
import '../surface.dart';
import 'code_editor_view.dart';
import 'code_error_strip.dart';
import 'code_eval_flash.dart';
import 'code_header.dart';
import 'code_projected_view.dart';
import 'code_seed.dart';

/// Live coding surface — Python editor with a working view (re_editor)
/// and a projected view (read-only, comments stripped). Ctrl+Enter
/// evaluates the block under the cursor through [evaluator]; a `fresh`
/// header toggle prefixes evaluations with `yse.cancel_all()`, and Python
/// tracebacks from the engine surface in a strip pinned under the editor
/// (design `docs/design/live-coding.md` §5).
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
  final ValueNotifier<bool> _fresh = ValueNotifier<bool>(false);
  final ValueNotifier<PythonTraceback?> _error =
      ValueNotifier<PythonTraceback?>(null);
  StreamSubscription<EvalEvent>? _eventsSub;

  /// The editor range (and `fresh` state) of the most recently dispatched
  /// block — what a later traceback line maps back onto for the error flash.
  ({int startLine, int endLine, bool fresh})? _lastBlock;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.seedSource);
    _flash = CodeEvalFlash();
    // The evaluator republishes engine tracebacks as EvalStderr frames; each one
    // fills the strip and, when it maps onto the last block, turns the flash red.
    _eventsSub = widget.evaluator.events.listen(_onEvalEvent);
  }

  void _onEvalEvent(EvalEvent event) {
    if (event is! EvalStderr) return;
    final traceback = PythonTraceback.parse(event.text);
    _error.value = traceback;
    _flashErrorIfOnBlock(traceback);
  }

  /// Re-fire the flash red over the last block when [traceback] traces to a line
  /// inside it. A callback-origin traceback (no `<script>` frame) or one whose
  /// line falls outside the block leaves the flash alone — the strip still shows
  /// it verbatim (issue #232).
  void _flashErrorIfOnBlock(PythonTraceback traceback) {
    final last = _lastBlock;
    final line = traceback.scriptLine;
    if (last == null || line == null) return;
    // A `fresh` submission prepends `yse.cancel_all()` as script line 1, so the
    // block's own lines start at 2 — shift the valid window by that offset.
    final freshOffset = last.fresh ? 1 : 0;
    final lineCount = last.endLine - last.startLine + 1;
    if (line < 1 + freshOffset || line > lineCount + freshOffset) return;
    _flash.fire(
      startLine: last.startLine,
      endLine: last.endLine,
      kind: CodeEvalFlashKind.error,
    );
  }

  void _onBlockEvaluated({
    required int startLine,
    required int endLine,
    required bool fresh,
  }) {
    _lastBlock = (startLine: startLine, endLine: endLine, fresh: fresh);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _error.dispose();
    _fresh.dispose();
    _flash.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: Column(
        children: [
          CodeHeader(fresh: _fresh),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.session.projection,
              builder: (context, projected, _) {
                if (projected) {
                  return CodeProjectedView(
                    controller: _controller,
                    flash: _flash,
                  );
                }
                return CodeEditorView(
                  controller: _controller,
                  evaluator: widget.evaluator,
                  flash: _flash,
                  fresh: _fresh,
                  onEvaluated: _onBlockEvaluated,
                );
              },
            ),
          ),
          ValueListenableBuilder<PythonTraceback?>(
            valueListenable: _error,
            builder: (context, traceback, _) {
              if (traceback == null) return const SizedBox.shrink();
              return CodeErrorStrip(
                traceback: traceback,
                onDismiss: () => _error.value = null,
              );
            },
          ),
        ],
      ),
    );
  }
}
