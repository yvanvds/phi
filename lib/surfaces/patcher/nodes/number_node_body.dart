import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/patcher/patch_node.dart';
import '../../../engine/state/patcher_controller.dart';

/// Body for the `.i` (int) and `.f` (float) number nodes — an editable readout
/// that pushes its value into the object's hot inlet via
/// [PatcherController.setControlValue] (`sendFloat`) on submit, then displays
/// the value the native side reports back through `guiValue` (design
/// `docs/design/patcher.md` §7).
///
/// The display is the engine's `guiValue`, re-read after each push, so a number
/// box shows the authoritative value rather than a Dart-side echo — the same
/// value a cable into its inlet would set.
///
/// Editing follows Max (issue #353): clicking the readout takes focus and
/// selects the whole value, so typing replaces it; **Enter** commits and pushes;
/// moving focus away commits whatever was typed; **Escape** throws the edit away
/// and snaps back to the live `guiValue`. The canvas leaves both the press and
/// the keys alone while this field holds focus, so Backspace edits text here
/// instead of deleting the selected nodes.
class NumberNodeBody extends StatefulWidget {
  const NumberNodeBody({
    required this.node,
    required this.controller,
    this.integer = false,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// `.i` rounds to a whole number; `.f` keeps the fractional value.
  final bool integer;

  @override
  State<NumberNodeBody> createState() => _NumberNodeBodyState();
}

class _NumberNodeBodyState extends State<NumberNodeBody> {
  late final TextEditingController _text = TextEditingController(
    text: _display(),
  );
  final FocusNode _focus = FocusNode(debugLabel: 'number-node-field');

  /// Whether the user has typed since the last commit. Focus-loss commits only
  /// a dirty field, so merely clicking through a number box never re-pushes its
  /// own value back into the graph.
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    // Detach first: disposing a focused node unfocuses it, and the listener
    // would otherwise commit into a half-torn-down widget.
    _focus.removeListener(_onFocusChange);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _selectAll();
    } else if (_dirty) {
      _commit(_text.text);
    }
  }

  /// The formatted `guiValue`, or `0` before any value has been set.
  String _display() {
    final gui = widget.controller.guiValueOf(widget.node.id);
    final d = double.tryParse(gui);
    if (d == null) return gui.isEmpty ? '0' : gui;
    return _format(d);
  }

  String _format(double d) => widget.integer
      ? '${d.round()}'
      : (d == d.roundToDouble() ? '${d.toInt()}' : '$d');

  void _commit(String raw) {
    final d = double.tryParse(raw.trim());
    _dirty = false;
    if (d == null) {
      // Reject unparseable input: snap the field back to the live value.
      _showLiveValue();
      return;
    }
    widget.controller.setControlValue(
      widget.node.id,
      inlet: 0,
      value: widget.integer ? d.roundToDouble() : d,
    );
    // Re-read the authoritative display value the native side now reports.
    _showLiveValue();
  }

  /// Drop the edit and snap back to the engine's value, then hand the keyboard
  /// back so the canvas' own shortcuts work again.
  void _revert() {
    _dirty = false;
    _showLiveValue();
    _focus.unfocus();
  }

  /// Write the live `guiValue` into the field. While the box still holds focus
  /// the value stays selected, so the next keystroke replaces it — the same
  /// state a fresh click leaves it in.
  void _showLiveValue() {
    final text = _display();
    _text.value = TextEditingValue(
      text: text,
      selection: _focus.hasFocus
          ? TextSelection(baseOffset: 0, extentOffset: text.length)
          : TextSelection.collapsed(offset: text.length),
    );
  }

  void _selectAll() => _text.selection = TextSelection(
    baseOffset: 0,
    extentOffset: _text.text.length,
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: PhiColors.bg2,
          borderRadius: PhiRadii.all1,
          border: Border.all(color: PhiColors.line2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // Escape lives here rather than on the canvas: the canvas deliberately
        // ignores keys while a descendant holds focus (issue #353), and this
        // binding sits between the field and the canvas so it wins either way.
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revert},
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: (_) => _dirty = true,
            onSubmitted: _commit,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: PhiType.mono().copyWith(color: PhiColors.fg0),
            textAlign: TextAlign.right,
          ),
        ),
      ),
    );
  }
}
