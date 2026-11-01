import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/tokens/phi_voices.dart';
import '../../../design/widgets/patcher/patch_text_edit_box.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';
import 'gui_value_link.dart';

/// Body for the `.textedit` node — an editable one-line field whose committed
/// text becomes the object's whole state through
/// [PatcherController.restoreGuiValueOf] (issue #470). That write *is* a list on
/// inlet 0, which the engine's `gTextEdit` stores and sends on, so committing
/// the field is what puts the text into the graph.
///
/// Editing follows the number box (issue #353), because it is the same kind
/// of field on the same canvas: a click takes focus and selects the whole text,
/// so typing replaces it; **Enter** commits; moving focus away commits whatever
/// was typed; **Escape** throws the edit away and snaps back to the object's
/// text. The canvas leaves keys alone while this field holds focus, so
/// Backspace edits text here instead of deleting the selected nodes.
///
/// The field shows the object's `guiValue` — its stored text — and a
/// [GuiValueLink] keeps it current, so text arriving over a cable shows up on
/// its own; a field that **holds focus** is left alone, because someone is
/// typing in it. The engine holds at most [maxLength] characters and ignores a
/// longer text outright, so the field stops there.
class TexteditNodeBody extends StatefulWidget {
  const TexteditNodeBody({
    required this.node,
    required this.controller,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// The engine's text capacity (`gTextEdit::TEXT_CAPACITY`).
  static const int maxLength = 256;

  @override
  State<TexteditNodeBody> createState() => _TexteditNodeBodyState();
}

class _TexteditNodeBodyState extends State<TexteditNodeBody> {
  late final GuiValueLink _gui;
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode(debugLabel: 'textedit-node-field');

  /// Whether the user has typed since the last commit — focus-loss commits
  /// only a dirty field, so clicking through one never re-sends its text.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _gui = GuiValueLink(
      node: widget.node,
      controller: widget.controller,
      onInbound: _follow,
    );
    _text = TextEditingController(text: _gui.value);
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(TexteditNodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _gui.rebind(widget.node);
  }

  @override
  void dispose() {
    // Detach first: disposing a focused node unfocuses it, and the listener
    // would otherwise commit into a half-torn-down widget.
    _focus.removeListener(_onFocusChange);
    _gui.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _follow(String raw) {
    if (_focus.hasFocus) return;
    if (_text.text == raw) return;
    setState(_showLiveValue);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    } else if (_dirty) {
      _commit(_text.text);
    }
    // The underline follows the focus.
    setState(() {});
  }

  void _commit(String text) {
    _dirty = false;
    widget.controller.restoreGuiValueOf(widget.node.id, text);
    _showLiveValue();
  }

  void _revert() {
    _dirty = false;
    _showLiveValue();
    _focus.unfocus();
  }

  /// Write the object's text into the field. While the field still holds
  /// focus the text stays selected, so the next keystroke replaces it.
  void _showLiveValue() {
    final text = _gui.value;
    _text.value = TextEditingValue(
      text: text,
      selection: _focus.hasFocus
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PatchTextEditBox(
      focused: _focus.hasFocus,
      accent: PhiVoices.color(widget.node.voice),
      // Escape lives here rather than on the canvas, which ignores keys while
      // a descendant holds focus (issue #353).
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revert},
        child: TextField(
          controller: _text,
          focusNode: _focus,
          onChanged: (_) => _dirty = true,
          onSubmitted: _commit,
          inputFormatters: [
            LengthLimitingTextInputFormatter(TexteditNodeBody.maxLength),
          ],
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          style: PhiType.monoS().copyWith(color: PhiColors.fg0),
        ),
      ),
    );
  }
}
