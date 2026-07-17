import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/transforms/velocity_curve.dart';
import '../../../domain/midi/transforms/velocity_curve_shape.dart';
import '../../../domain/midi/transforms/velocity_to_parameter_transform.dart';
import 'editor_fields.dart';

/// Typed editor for a [VelocityToParameterTransform] (issue #108): the engine
/// parameter it drives plus its declarative [VelocityCurve] — shape, output
/// range, and (for the stepped shape) the number of levels.
///
/// The curve used to be a bare `double Function(double)` callback with nothing
/// to edit; now it is a value model, so this dialog reshapes it in place. The
/// `steps` field only appears for [VelocityCurveShape.stepped] — the other
/// shapes ignore it. Every edit applies **live** through
/// [MidiTransformChain.replaceAt], like the other typed editors; a parse-invalid
/// field keeps the last valid value, the same contract the scalar editor uses.
class VelocityCurveEditor extends StatefulWidget {
  const VelocityCurveEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;
  final int index;

  @override
  State<VelocityCurveEditor> createState() => _VelocityCurveEditorState();
}

class _VelocityCurveEditorState extends State<VelocityCurveEditor> {
  late VelocityToParameterTransform _current =
      widget.chain.transforms[widget.index] as VelocityToParameterTransform;

  late final TextEditingController _parameter = TextEditingController(
    text: _current.parameter,
  );
  late final TextEditingController _valueAt0 = TextEditingController(
    text: _formatDouble(_current.curve.valueAt0),
  );
  late final TextEditingController _valueAt1 = TextEditingController(
    text: _formatDouble(_current.curve.valueAt1),
  );
  late final TextEditingController _steps = TextEditingController(
    text: '${_current.curve.steps}',
  );

  static String _formatDouble(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    _parameter.dispose();
    _valueAt0.dispose();
    _valueAt1.dispose();
    _steps.dispose();
    super.dispose();
  }

  void _applyParameter(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _replace(_current.copyWith(parameter: trimmed));
  }

  void _applyShape(VelocityCurveShape shape) {
    _replace(_current.copyWith(curve: _current.curve.copyWith(shape: shape)));
    setState(() {}); // repaint the choice's label and reveal/hide `steps`.
  }

  void _applyValueAt0(String text) {
    final value = double.tryParse(text);
    if (value == null) return;
    _replace(
      _current.copyWith(curve: _current.curve.copyWith(valueAt0: value)),
    );
  }

  void _applyValueAt1(String text) {
    final value = double.tryParse(text);
    if (value == null) return;
    _replace(
      _current.copyWith(curve: _current.curve.copyWith(valueAt1: value)),
    );
  }

  void _applySteps(String text) {
    final value = int.tryParse(text);
    if (value == null) return;
    _replace(
      _current.copyWith(
        curve: _current.curve.copyWith(steps: value.clamp(1, 64)),
      ),
    );
  }

  void _replace(VelocityToParameterTransform next) {
    if (widget.index >= widget.chain.transforms.length) return;
    _current = next;
    widget.chain.replaceAt(widget.index, next);
  }

  @override
  Widget build(BuildContext context) {
    final shape = _current.curve.shape;
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit velocity curve',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EditorRow(
              label: 'param',
              child: EditorTextInput(
                controller: _parameter,
                onChanged: _applyParameter,
                hintText: 'filter.cutoff',
              ),
            ),
            EditorRow(
              label: 'shape',
              child: EditorChoice<VelocityCurveShape>(
                value: shape,
                options: [
                  for (final s in VelocityCurveShape.values) (s, s.label),
                ],
                onChanged: _applyShape,
              ),
            ),
            EditorRow(
              label: 'value @ vel 0',
              child: EditorTextInput(
                controller: _valueAt0,
                onChanged: _applyValueAt0,
              ),
            ),
            EditorRow(
              label: 'value @ vel 1',
              child: EditorTextInput(
                controller: _valueAt1,
                onChanged: _applyValueAt1,
              ),
            ),
            if (shape == VelocityCurveShape.stepped)
              EditorRow(
                label: 'steps',
                child: EditorTextInput(
                  controller: _steps,
                  onChanged: _applySteps,
                ),
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
