import 'package:flutter/material.dart';

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
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
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

  void _submit(String raw) {
    final d = double.tryParse(raw.trim());
    if (d == null) {
      // Reject unparseable input: snap the field back to the live value.
      setState(() => _text.text = _display());
      return;
    }
    final value = widget.integer ? d.roundToDouble() : d;
    widget.controller.setControlValue(widget.node.id, inlet: 0, value: value);
    // Re-read the authoritative display value the native side now reports.
    setState(() => _text.text = _display());
  }

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
        child: TextField(
          controller: _text,
          focusNode: _focus,
          onSubmitted: _submit,
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
    );
  }
}
