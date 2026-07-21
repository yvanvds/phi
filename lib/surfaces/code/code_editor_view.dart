import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/code/completion/phi_completion_resolver.dart';
import '../../domain/code/python_block_splitter.dart';
import '../../domain/project/project_registry.dart';
import '../../engine/bridge/code_evaluator.dart';
import 'code_eval_flash.dart';
import 'code_highlight_theme.dart';
import 'completion/phi_completion_list_view.dart';
import 'completion/phi_completion_prompts_builder.dart';

/// Sent when Ctrl+Enter is pressed inside the editor — handled by the
/// `Actions` wrapper around the [CodeEditor].
class EvaluateBlockIntent extends Intent {
  const EvaluateBlockIntent();
}

/// Reports the block a Ctrl+Enter just dispatched — its editor line range and
/// whether the `fresh` prefix was applied — so the surface can map a later
/// traceback line back onto the editor for the error flash (issue #232).
typedef OnBlockEvaluated =
    void Function({
      required int startLine,
      required int endLine,
      required bool fresh,
    });

/// Custom shortcut activator builder: identical to re_editor's default
/// except Ctrl+Enter is removed from `newLine`, so it falls through to
/// the outer `Shortcuts` widget where `EvaluateBlockIntent` lives.
class _PhiCodeShortcuts extends CodeShortcutsActivatorsBuilder {
  const _PhiCodeShortcuts();

  static const _fallback = DefaultCodeShortcutsActivatorsBuilder();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    final base = _fallback.build(type);
    if (base == null) return null;
    if (type != CodeShortcutType.newLine) return base;
    return [
      for (final activator in base)
        if (!(activator is SingleActivator &&
            activator.trigger == LogicalKeyboardKey.enter &&
            activator.control))
          activator,
    ];
  }
}

/// Working view of the Code surface — full `re_editor` `CodeEditor`
/// with Python highlight, line numbers, and Ctrl+Enter wired to
/// [evaluator].
class CodeEditorView extends StatefulWidget {
  const CodeEditorView({
    required this.controller,
    required this.evaluator,
    required this.flash,
    required this.fresh,
    this.registry,
    this.onEvaluated,
    super.key,
  });

  /// Key on the flash tint overlay, so a test can read which colour the flash
  /// painted (fuchsia for a clean eval, red for an error).
  static const Key flashOverlayKey = ValueKey('code-eval-flash-overlay');

  final CodeLineEditingController controller;
  final CodeEvaluator evaluator;
  final CodeEvalFlash flash;

  /// The live registry the completion popup reads (design §6). When `null`
  /// (the bare Phase-1 path with no project), the editor hosts no completion —
  /// plain Python typing only.
  final ProjectRegistry? registry;

  /// The live `fresh` flag from the header. When set, the block dispatched by
  /// Ctrl+Enter is prefixed with `yse.cancel_all()` so it replaces (rather than
  /// layers on) what is scheduled (design §5, §8 decision 3).
  final ValueListenable<bool> fresh;

  /// Notified with the block range each Ctrl+Enter dispatched, for the surface's
  /// error-line mapping. Optional so the view stays usable without it.
  final OnBlockEvaluated? onEvaluated;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  late final CodeHighlightTheme _highlightTheme;

  /// The registry-driven completion adapter, rebuilt when the registry changes.
  /// `null` when no registry is supplied — then the editor hosts no popup.
  PhiCompletionPromptsBuilder? _prompts;

  @override
  void initState() {
    super.initState();
    _highlightTheme = buildPythonHighlightTheme();
    _rebuildPrompts();
  }

  @override
  void didUpdateWidget(covariant CodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.registry, oldWidget.registry)) {
      _rebuildPrompts();
    }
  }

  void _rebuildPrompts() {
    final registry = widget.registry;
    _prompts = registry == null
        ? null
        : PhiCompletionPromptsBuilder(PhiCompletionResolver(registry));
  }

  Future<void> _evaluateBlockUnderCursor() async {
    final source = widget.controller.text;
    final blocks = splitIntoBlocks(source);
    if (blocks.isEmpty) return;
    final caretLine = widget.controller.selection.extentIndex;
    final block = blockAtLine(blocks, caretLine) ?? blocks.last;
    final fresh = widget.fresh.value;
    // Green (ok) flash up front; a later traceback re-fires it red (issue #232).
    widget.flash.fire(startLine: block.startLine, endLine: block.endLine);
    widget.onEvaluated?.call(
      startLine: block.startLine,
      endLine: block.endLine,
      fresh: fresh,
    );
    // Layering is the default; `fresh` prefixes `yse.cancel_all()` so the block
    // replaces what is scheduled rather than stacking on it (design §5).
    final submitted = fresh
        ? 'yse.cancel_all()\n${block.source}'
        : block.source;
    await widget.evaluator.evaluate(submitted);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            EvaluateBlockIntent(),
      },
      child: Actions(
        actions: {
          EvaluateBlockIntent: CallbackAction<EvaluateBlockIntent>(
            onInvoke: (_) {
              _evaluateBlockUnderCursor();
              return null;
            },
          ),
        },
        child: Stack(
          children: [
            _withCompletion(_buildEditor()),
            Positioned.fill(
              child: IgnorePointer(child: _FlashOverlay(flash: widget.flash)),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps [editor] in `re_editor`'s [CodeAutocomplete] when a registry is
  /// available, hosting the registry-driven popup (design §6); otherwise returns
  /// the plain editor so a project-less surface has no completion.
  Widget _withCompletion(Widget editor) {
    final prompts = _prompts;
    if (prompts == null) return editor;
    return CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) =>
          PhiCompletionListView(notifier: notifier, onSelected: onSelected),
      promptsBuilder: prompts,
      child: editor,
    );
  }

  Widget _buildEditor() {
    return CodeEditor(
      controller: widget.controller,
      wordWrap: false,
      autofocus: false,
      shortcutsActivatorsBuilder: const _PhiCodeShortcuts(),
      style: CodeEditorStyle(
        fontSize: 13,
        fontFamily: 'JetBrainsMono',
        backgroundColor: PhiColors.bg0,
        textColor: PhiColors.fg1,
        cursorColor: PhiColors.voice1,
        cursorLineColor: PhiColors.bg1,
        selectionColor: PhiColors.voice1Soft,
        codeTheme: _highlightTheme,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PhiSpacing.s3,
        vertical: PhiSpacing.s2,
      ),
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return Row(
              children: [
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: PhiType.monoS().copyWith(color: PhiColors.fg3),
                ),
              ],
            );
          },
    );
  }
}

class _FlashOverlay extends StatelessWidget {
  const _FlashOverlay({required this.flash});

  final CodeEvalFlash flash;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flash,
      builder: (context, _) {
        if (flash.intensity <= 0.0) return const SizedBox.shrink();
        final tint = flash.kind == CodeEvalFlashKind.error
            ? PhiColors.hot
            : PhiColors.voice1Soft;
        return ColoredBox(
          key: CodeEditorView.flashOverlayKey,
          color: tint.withAlpha((0x20 * flash.intensity).round()),
        );
      },
    );
  }
}
