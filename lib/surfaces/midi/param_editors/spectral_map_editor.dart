import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/transforms/spectral_mapping_transform.dart';
import 'editor_fields.dart';

/// Typed editor for a [SpectralMappingTransform] (issue #95): the pitch→pitch
/// lookup table as an editable list of rows.
///
/// Each row is `source semitone → target pitch` (the target is a fractional
/// MIDI pitch, so the table can retune onto a microtonal grid). Rows whose
/// source or target doesn't parse are simply dropped from the rebuilt table —
/// the same "keep the last valid value" contract the scalar editor uses. Every
/// edit applies **live** through [MidiTransformChain.replaceAt]; a sparse table
/// only touches the pitch classes it names.
class SpectralMapEditor extends StatefulWidget {
  const SpectralMapEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;
  final int index;

  @override
  State<SpectralMapEditor> createState() => _SpectralMapEditorState();
}

class _SpectralMapEditorState extends State<SpectralMapEditor> {
  late SpectralMappingTransform _current =
      widget.chain.transforms[widget.index] as SpectralMappingTransform;

  late final List<_MapRow> _rows = [
    for (final entry
        in (_current.table.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))))
      _MapRow.of(entry.key, entry.value),
  ];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Rebuilds the table from the current rows and applies it live. Rows that
  /// don't parse to a valid `int → double` pair are dropped.
  void _apply() {
    if (widget.index >= widget.chain.transforms.length) return;
    final table = <int, double>{};
    for (final row in _rows) {
      final source = int.tryParse(row.source.text);
      final target = double.tryParse(row.target.text);
      if (source == null || target == null) continue;
      table[source.clamp(0, 127)] = target.clamp(0.0, 127.0);
    }
    _current = _current.copyWith(table: table);
    widget.chain.replaceAt(widget.index, _current);
  }

  void _addRow() => setState(() => _rows.add(_MapRow.empty()));

  void _removeRow(int i) {
    setState(() => _rows.removeAt(i).dispose());
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit pitch map',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'no mappings — every pitch passes through',
                  style: PhiType.monoS().copyWith(
                    fontSize: 11,
                    color: PhiColors.fg3,
                  ),
                ),
              ),
            for (var i = 0; i < _rows.length; i++)
              _MapRowView(
                row: _rows[i],
                onChanged: _apply,
                onRemove: () => _removeRow(i),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _addRow,
                child: const Text('+ add mapping'),
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

/// The two controllers backing one table row.
class _MapRow {
  _MapRow.of(int source, double target)
    : source = TextEditingController(text: '$source'),
      target = TextEditingController(
        text: target == target.roundToDouble()
            ? '${target.toInt()}'
            : '$target',
      );

  _MapRow.empty()
    : source = TextEditingController(),
      target = TextEditingController();

  final TextEditingController source;
  final TextEditingController target;

  void dispose() {
    source.dispose();
    target.dispose();
  }
}

/// One `source → target` row with a delete affordance.
class _MapRowView extends StatelessWidget {
  const _MapRowView({
    required this.row,
    required this.onChanged,
    required this.onRemove,
  });

  final _MapRow row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: EditorTextInput(
              controller: row.source,
              onChanged: (_) => onChanged(),
              hintText: 'pitch',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '→',
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: PhiColors.fg3,
              ),
            ),
          ),
          Expanded(
            child: EditorTextInput(
              controller: row.target,
              onChanged: (_) => onChanged(),
              hintText: 'target',
            ),
          ),
          EditorRemoveButton(onRemove: onRemove),
        ],
      ),
    );
  }
}
