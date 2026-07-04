import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/music_scale.dart';
import '../../../domain/midi/scale_tuning.dart';
import '../../../domain/midi/transforms/scale_conformance_transform.dart';
import 'editor_fields.dart';

/// Typed editor for a [ScaleConformanceTransform] (issue #95): a scale/tuning
/// preset picker plus the scalar tonic.
///
/// The tuning is a cents table with no natural text field, so it is chosen
/// from named presets — the seven diatonic modes and the two just-intonation
/// scales `ScaleTuning` ships. Picking one rebuilds the tuning; the tonic is a
/// plain fractional-MIDI number. Both apply **live** through
/// [MidiTransformChain.replaceAt] like the scalar editor.
class ScaleTuningEditor extends StatefulWidget {
  const ScaleTuningEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;
  final int index;

  @override
  State<ScaleTuningEditor> createState() => _ScaleTuningEditorState();
}

class _ScaleTuningEditorState extends State<ScaleTuningEditor> {
  late ScaleConformanceTransform _current =
      widget.chain.transforms[widget.index] as ScaleConformanceTransform;

  late final TextEditingController _tonic = TextEditingController(
    text: _formatDouble(_current.tonic),
  );

  /// The named presets the picker offers, in display order.
  static final List<(String, ScaleTuning)> _presets = [
    for (final scale in MusicScale.values)
      (scale.label, ScaleTuning.diatonic(scale)),
    ('just major', ScaleTuning.justMajor),
    ('just minor', ScaleTuning.justMinor),
  ];

  /// Label of the preset matching [tuning], or `null` when the tuning is a
  /// custom cents table none of the presets names.
  static String? _labelFor(ScaleTuning tuning) {
    for (final (label, preset) in _presets) {
      if (preset.periodCents == tuning.periodCents &&
          _sameCents(preset.degreesCents, tuning.degreesCents)) {
        return label;
      }
    }
    return null;
  }

  static bool _sameCents(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  static String _formatDouble(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    _tonic.dispose();
    super.dispose();
  }

  void _applyPreset(String label) {
    final tuning = _presets.firstWhere((p) => p.$1 == label).$2;
    _replace(_current.copyWith(tuning: tuning));
    setState(() {}); // repaint the choice's current label.
  }

  void _applyTonic(String text) {
    final value = double.tryParse(text);
    if (value == null) return;
    _replace(_current.copyWith(tonic: value.clamp(0.0, 127.0)));
  }

  void _replace(ScaleConformanceTransform next) {
    if (widget.index >= widget.chain.transforms.length) return;
    _current = next;
    widget.chain.replaceAt(widget.index, next);
  }

  @override
  Widget build(BuildContext context) {
    final current = _labelFor(_current.tuning);
    final options = [
      if (current == null) ('(custom)', '(custom)'),
      for (final (label, _) in _presets) (label, label),
    ];
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit scale',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EditorRow(
              label: 'scale',
              child: EditorChoice<String>(
                value: current ?? '(custom)',
                options: options,
                onChanged: _applyPreset,
              ),
            ),
            EditorRow(
              label: 'tonic',
              child: EditorTextInput(
                controller: _tonic,
                onChanged: _applyTonic,
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
