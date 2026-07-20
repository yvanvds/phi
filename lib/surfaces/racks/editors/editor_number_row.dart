import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';

/// A labelled integer field — the discrete counterpart to [EditorSliderRow] for
/// whole-number params (voice count, patch index, sample key ranges, FM operator
/// values).
///
/// A discrete edit, so it commits **immediately** on each parse-valid change
/// (there is no gesture to coalesce): the moment the text parses as an int it is
/// clamped to `[min, max]` and, if it moved, handed to [onCommit] as one
/// journaled edit. Non-numeric or empty text is simply not applied. The row owns
/// its [TextEditingController] and re-seeds it when [value] changes underneath it
/// (an undo, a kind switch).
class EditorNumberRow extends StatefulWidget {
  const EditorNumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommit,
    super.key,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onCommit;

  @override
  State<EditorNumberRow> createState() => _EditorNumberRowState();
}

class _EditorNumberRowState extends State<EditorNumberRow> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(EditorNumberRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed when the committed value changed from outside this field (undo,
    // selection swap) and the field isn't mid-edit of that same value.
    if (widget.value != oldWidget.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final parsed = int.tryParse(text);
    if (parsed == null) return;
    final clamped = parsed.clamp(widget.min, widget.max);
    if (clamped == widget.value) return;
    widget.onCommit(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
            ),
          ),
          SizedBox(
            width: 72,
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              ],
              textAlign: TextAlign.right,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}
