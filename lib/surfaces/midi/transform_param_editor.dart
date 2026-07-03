import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/midi/midi_transform.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/transform_param.dart';

/// Modal that edits a chip's scalar parameters in place (issue #71).
///
/// One text field per [TransformParam], in the transform's declared order.
/// Edits apply **live**: the moment a field's text parses as its param's type
/// it is clamped to the declared bounds and written back to the chain via
/// [MidiTransformChain.replaceAt], so the roll ghost and playback follow each
/// keystroke — the dialog's only button just dismisses it. Text that doesn't
/// parse (empty, a lone `-`) is simply not applied; the chain keeps the last
/// valid value.
class TransformParamEditor extends StatefulWidget {
  const TransformParamEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;

  /// Position of the edited transform in [chain]. Stable while the dialog is
  /// open — the chain only mutates through this same modal UI path.
  final int index;

  @override
  State<TransformParamEditor> createState() => _TransformParamEditorState();
}

class _TransformParamEditorState extends State<TransformParamEditor> {
  late MidiTransform _current = widget.chain.transforms[widget.index];
  late final List<TextEditingController> _controllers = [
    for (final p in _current.params)
      TextEditingController(text: _initialText(p)),
  ];

  static String _initialText(TransformParam p) => switch (p) {
    IntParam() => '${p.value}',
    DoubleParam() => _formatDouble(p.value),
  };

  /// `2.0` renders as `2` — the field is for musicians, not printf.
  static String _formatDouble(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parses [text] against the *declared* param [p] (bounds, int vs double)
  /// and, when valid, mutates the chip in place. The name is read from [p] but
  /// the value written through [_current], which tracks the edits already
  /// applied this session.
  void _apply(TransformParam p, String text) {
    final num? value = switch (p) {
      IntParam() => _clamp(int.tryParse(text), p.min, p.max),
      DoubleParam() => _clamp(double.tryParse(text), p.min, p.max),
    };
    if (value == null) return;
    if (widget.index >= widget.chain.transforms.length) return;
    _current = _current.withParam(p.name, value);
    widget.chain.replaceAt(widget.index, _current);
  }

  static num? _clamp(num? v, num? min, num? max) {
    if (v == null) return null;
    return v.clamp(min ?? v, max ?? v);
  }

  @override
  Widget build(BuildContext context) {
    final params = _current.params;
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit parameters',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < params.length; i++)
              _ParamRow(
                param: params[i],
                controller: _controllers[i],
                onChanged: (text) => _apply(params[i], text),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('done'),
        ),
      ],
    );
  }
}

/// One labelled field: param name on the left, its value field on the right.
class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.param,
    required this.controller,
    required this.onChanged,
  });

  final TransformParam param;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              param.name,
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: PhiColors.fg1,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: PhiColors.fg0,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
