import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/code/python_traceback.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/session/session_state.dart';
import '../../engine/bridge/code_evaluator.dart';
import '../../engine/engine.dart';
import '../../engine/state/code_library_controller.dart';
import '../surface.dart';
import 'code_editor_view.dart';
import 'code_error_strip.dart';
import 'code_eval_flash.dart';
import 'code_header.dart';
import 'code_library_panel.dart';
import 'code_projected_view.dart';
import 'code_seed.dart';

/// Live coding surface — Python editor with a working view (re_editor)
/// and a projected view (read-only, comments stripped). Ctrl+Enter
/// evaluates the block under the cursor through [evaluator]; a `fresh`
/// header toggle prefixes evaluations with `yse.cancel_all()`, and Python
/// tracebacks from the engine surface in a strip pinned under the editor
/// (design `docs/design/live-coding.md` §5).
///
/// When a [libraryController] is supplied (the app has a project), a script
/// **library panel** docks on the left: selecting a script swaps the editor's
/// content to it, and edits are journaled per idle pause into the `code.` entity
/// (issue #235). Without one (the bare Phase-1 path) the editor is a single
/// [seedSource]-seeded buffer.
///
/// The working/projected switch listens to [SessionState.projection],
/// so the top toolbar's projection toggle drives both this surface and
/// the rest of the workstation in lock-step.
class CodeSurface extends Surface {
  const CodeSurface({
    required this.engine,
    required this.session,
    required this.evaluator,
    this.libraryController,
    this.registry,
    String? seedSource,
    super.key,
  }) : _seedSource = seedSource;

  final PhiEngine engine;
  final SessionState session;
  final CodeEvaluator evaluator;

  /// The registry the completion popup reads (design §6). Defaults to the
  /// engine's live registry (bound to the open project); an explicit registry is
  /// mostly a test seam.
  final ProjectRegistry? registry;

  /// Drives the script library panel + the open-script editor swap. `null` in
  /// the bare Phase-1 path (no project); then the editor is a single seeded
  /// buffer with no panel.
  final CodeLibraryController? libraryController;

  final String? _seedSource;

  @override
  Widget build(BuildContext context) {
    return _CodeViewport(
      session: session,
      evaluator: evaluator,
      libraryController: libraryController,
      registry: registry ?? engine.mixRegistry,
      seedSource: _seedSource ?? codeSurfaceSeed,
    );
  }
}

class _CodeViewport extends StatefulWidget {
  const _CodeViewport({
    required this.session,
    required this.evaluator,
    required this.libraryController,
    required this.registry,
    required this.seedSource,
  });

  final SessionState session;
  final CodeEvaluator evaluator;
  final CodeLibraryController? libraryController;
  final ProjectRegistry registry;
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

  /// True while [_controller]'s text is being replaced from the library (a
  /// script swap), so the resulting change notification isn't mistaken for a
  /// performer edit and re-journaled.
  bool _applyingRemote = false;

  /// The last library revision the editor loaded, and the last text it forwarded
  /// — so a cursor move (which also notifies) doesn't churn the edit journal.
  int _appliedRevision = 0;
  String _lastEditorText = '';

  /// The editor range (and `fresh` state) of the most recently dispatched
  /// block — what a later traceback line maps back onto for the error flash.
  ({int startLine, int endLine, bool fresh})? _lastBlock;

  CodeLibraryController? get _library => widget.libraryController;

  /// The text the editor should show for the current library state: the open
  /// script's source, or — when nothing is open (no library, or an empty `code.`
  /// namespace) — the [seedSource] fallback, so the surface is never blank. A
  /// genuinely open but empty script still shows empty.
  String _textForLibrary() {
    final library = _library;
    if (library == null || library.openAddress == null) {
      return widget.seedSource;
    }
    return library.openSource;
  }

  @override
  void initState() {
    super.initState();
    final library = _library;
    final initialText = _textForLibrary();
    _controller = CodeLineEditingController.fromText(initialText);
    _lastEditorText = initialText;
    _flash = CodeEvalFlash();
    if (library != null) {
      _appliedRevision = library.openRevision;
      library.addListener(_onLibraryChanged);
      _controller.addListener(_onEditorChanged);
    }
    // The evaluator republishes engine tracebacks as EvalStderr frames; each one
    // fills the strip and, when it maps onto the last block, turns the flash red.
    _eventsSub = widget.evaluator.events.listen(_onEvalEvent);
  }

  /// Reload the editor from the library when a genuine swap moved the open
  /// revision — a selection, a rename-of-open, or a project rebind. Guarded so
  /// the programmatic text replacement isn't re-journaled as a performer edit.
  void _onLibraryChanged() {
    final library = _library;
    if (library == null) return;
    if (library.openRevision == _appliedRevision) return;
    _appliedRevision = library.openRevision;
    final text = _textForLibrary();
    _applyingRemote = true;
    _controller.text = text;
    _applyingRemote = false;
    _lastEditorText = text;
  }

  /// Forward a performer edit to the library for coalesced journaling. Skips the
  /// programmatic swap (guarded) and pure cursor moves (text unchanged).
  void _onEditorChanged() {
    if (_applyingRemote) return;
    final library = _library;
    if (library == null) return;
    final text = _controller.text;
    if (text == _lastEditorText) return;
    _lastEditorText = text;
    library.onEditorChanged(text);
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
    final library = _library;
    if (library != null) {
      _controller.removeListener(_onEditorChanged);
      library.removeListener(_onLibraryChanged);
      // Commit any un-journaled edit before the surface goes away.
      library.flushPendingEdits();
    }
    _eventsSub?.cancel();
    _error.dispose();
    _fresh.dispose();
    _flash.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorColumn = Column(
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
                registry: widget.registry,
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
    );

    final library = _library;
    return Container(
      color: PhiColors.bg0,
      child: library == null
          ? editorColumn
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CodeLibraryPanel(controller: library),
                Expanded(child: editorColumn),
              ],
            ),
    );
  }
}
