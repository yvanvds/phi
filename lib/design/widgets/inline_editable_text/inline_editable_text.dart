import 'package:flutter/material.dart';

import '../../tokens/phi_colors.dart';

/// Text that becomes a TextField when tapped. Commits on Enter or on blur.
/// Used for inline scene-name editing in the top toolbar.
class InlineEditableText extends StatefulWidget {
  const InlineEditableText({
    required this.value,
    required this.onChanged,
    this.style,
    this.maxWidth = 240,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextStyle? style;
  final double maxWidth;

  @override
  State<InlineEditableText> createState() => _InlineEditableTextState();
}

class _InlineEditableTextState extends State<InlineEditableText> {
  bool _editing = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(InlineEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      _commit();
    }
  }

  void _commit() {
    if (!_editing) return;
    setState(() => _editing = false);
    if (_controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
  }

  void _startEditing() {
    setState(() => _editing = true);
    _controller.text = widget.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    if (_editing) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: IntrinsicWidth(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: style,
            cursorColor: PhiColors.voice1,
            cursorWidth: 1,
            onSubmitted: (_) => _commit(),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        onTap: _startEditing,
        child: Text(widget.value, style: style),
      ),
    );
  }
}
