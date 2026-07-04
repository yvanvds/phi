import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/transforms/split_voice.dart';
import '../../../domain/midi/transforms/splitting_transform.dart';
import 'editor_fields.dart';

/// Typed editor for a [SplittingTransform] (issue #95): the layer list every
/// source note is copied onto.
///
/// Each row is one [SplitVoice] — a target channel (blank keeps the source
/// channel), a semitone pitch offset, and a velocity scale. The output holds
/// `notes × voices` copies, so a single default row is the identity and two
/// rows double every note. Edits apply **live** through
/// [MidiTransformChain.replaceAt]; a row whose numbers don't parse falls back
/// to a passthrough [SplitVoice] rather than dropping the layer.
class SplitVoicesEditor extends StatefulWidget {
  const SplitVoicesEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;
  final int index;

  @override
  State<SplitVoicesEditor> createState() => _SplitVoicesEditorState();
}

class _SplitVoicesEditorState extends State<SplitVoicesEditor> {
  late SplittingTransform _current =
      widget.chain.transforms[widget.index] as SplittingTransform;

  late final List<_VoiceRow> _rows = [
    for (final voice in _current.voices) _VoiceRow.of(voice),
  ];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _apply() {
    if (widget.index >= widget.chain.transforms.length) return;
    final voices = [for (final row in _rows) row.toVoice()];
    _current = _current.copyWith(voices: voices);
    widget.chain.replaceAt(widget.index, _current);
  }

  void _addRow() {
    setState(() => _rows.add(_VoiceRow.of(const SplitVoice())));
    _apply();
  }

  void _removeRow(int i) {
    setState(() => _rows.removeAt(i).dispose());
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit split layers',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeaderRow(),
            for (var i = 0; i < _rows.length; i++)
              _VoiceRowView(
                row: _rows[i],
                onChanged: _apply,
                onRemove: () => _removeRow(i),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _addRow,
                child: const Text('+ add layer'),
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

/// Controllers for one layer's three fields.
class _VoiceRow {
  _VoiceRow.of(SplitVoice voice)
    : channel = TextEditingController(
        text: voice.channel == null ? '' : '${voice.channel}',
      ),
      pitch = TextEditingController(text: '${voice.pitchOffset}'),
      velocity = TextEditingController(
        text: voice.velocityScale == voice.velocityScale.roundToDouble()
            ? '${voice.velocityScale.toInt()}'
            : '${voice.velocityScale}',
      );

  final TextEditingController channel;
  final TextEditingController pitch;
  final TextEditingController velocity;

  /// The [SplitVoice] this row currently describes. A blank channel maps to
  /// `null` ("keep source channel"); unparseable numbers fall back to the
  /// passthrough defaults so a half-typed field never drops the layer.
  SplitVoice toVoice() => SplitVoice(
    channel: channel.text.trim().isEmpty ? null : int.tryParse(channel.text),
    pitchOffset: int.tryParse(pitch.text) ?? 0,
    velocityScale: double.tryParse(velocity.text) ?? 1.0,
  );

  void dispose() {
    channel.dispose();
    pitch.dispose();
    velocity.dispose();
  }
}

/// Column labels above the layer rows.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(
        text,
        style: PhiType.monoS().copyWith(fontSize: 8, color: PhiColors.fg3),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 2),
      child: Row(
        children: [cell('CH', 72), cell('PITCH ±', 72), cell('VEL ×', 72)],
      ),
    );
  }
}

/// One layer row: channel · pitch offset · velocity scale · remove.
class _VoiceRowView extends StatelessWidget {
  const _VoiceRowView({
    required this.row,
    required this.onChanged,
    required this.onRemove,
  });

  final _VoiceRow row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String hint) => SizedBox(
      width: 64,
      child: EditorTextInput(
        controller: c,
        onChanged: (_) => onChanged(),
        hintText: hint,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: field(row.channel, 'keep'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: field(row.pitch, '0'),
          ),
          field(row.velocity, '1'),
          const Spacer(),
          EditorRemoveButton(onRemove: onRemove),
        ],
      ),
    );
  }
}
