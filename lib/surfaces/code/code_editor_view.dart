import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/code/python_block_splitter.dart';
import '../../engine/bridge/code_evaluator.dart';
import 'code_eval_flash.dart';
import 'code_highlight_theme.dart';

/// Sent when Ctrl+Enter is pressed inside the editor — handled by the
/// `Actions` wrapper around the [CodeEditor].
class EvaluateBlockIntent extends Intent {
  const EvaluateBlockIntent();
}

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
    super.key,
  });

  final CodeLineEditingController controller;
  final CodeEvaluator evaluator;
  final CodeEvalFlash flash;

  @override
  State<CodeEditorView> createState() => _CodeEditorViewState();
}

class _CodeEditorViewState extends State<CodeEditorView> {
  late final CodeHighlightTheme _highlightTheme;

  @override
  void initState() {
    super.initState();
    _highlightTheme = buildPythonHighlightTheme();
  }

  Future<void> _evaluateBlockUnderCursor() async {
    final source = widget.controller.text;
    final blocks = splitIntoBlocks(source);
    if (blocks.isEmpty) return;
    final caretLine = widget.controller.selection.extentIndex;
    final block = blockAtLine(blocks, caretLine) ?? blocks.last;
    widget.flash.fire(startLine: block.startLine, endLine: block.endLine);
    await widget.evaluator.evaluate(block.source);
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
            CodeEditor(
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
                          textStyle: PhiType.monoS().copyWith(
                            color: PhiColors.fg3,
                          ),
                        ),
                      ],
                    );
                  },
            ),
            Positioned.fill(
              child: IgnorePointer(child: _FlashOverlay(flash: widget.flash)),
            ),
          ],
        ),
      ),
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
        return ColoredBox(
          color: PhiColors.voice1Soft.withAlpha(
            (0x20 * flash.intensity).round(),
          ),
        );
      },
    );
  }
}
