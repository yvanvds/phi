import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/transforms/conditional_muting_transform.dart';
import '../../../domain/midi/transforms/note_comparison.dart';
import '../../../domain/midi/transforms/note_condition.dart';
import '../../../domain/midi/transforms/note_field.dart';
import 'editor_fields.dart';

/// Typed editor for a [ConditionalMutingTransform] (issue #109): the declarative
/// [NoteCondition] deciding which notes get muted.
///
/// The predicate used to be a bare `bool Function(MidiNote)` callback with
/// nothing to edit; now it is a value model, so this dialog rebuilds it in
/// place. The performer says "mute when [any / all] of" a list of leaf
/// conditions — each a note field (pitch · velocity · channel · start), a
/// comparison, and a threshold. A note that matches is dropped; an empty list
/// mutes nothing, so the catalogue's keep-all default becomes meaningful through
/// editing alone. Every edit applies **live** through
/// [MidiTransformChain.replaceAt], like the other typed editors; a parse-invalid
/// threshold keeps the last valid value, the same contract the scalar editor
/// uses.
class NotePredicateEditor extends StatefulWidget {
  const NotePredicateEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;
  final int index;

  @override
  State<NotePredicateEditor> createState() => _NotePredicateEditorState();
}

class _NotePredicateEditorState extends State<NotePredicateEditor> {
  late ConditionalMutingTransform _current =
      widget.chain.transforms[widget.index] as ConditionalMutingTransform;

  late NoteConditionCombinator _combinator = _initialGroup.combinator;
  // Only leaf conditions are edited here (the editor works one level deep); the
  // model can nest groups, but nothing produces them, so recovering the leaves
  // is loss-free in practice.
  late final List<NoteFieldCondition> _conditions = [
    for (final c in _initialGroup.conditions)
      if (c is NoteFieldCondition) c,
  ];
  // Stable ids so a removed condition doesn't shuffle sibling row state.
  late final List<int> _ids = [for (var i = 0; i < _conditions.length; i++) i];
  late int _nextId = _conditions.length;

  NoteConditionGroup get _initialGroup {
    final condition = _current.condition;
    return condition is NoteConditionGroup
        ? condition
        : const NoteConditionGroup.empty();
  }

  void _apply() {
    if (widget.index >= widget.chain.transforms.length) return;
    _current = _current.copyWith(
      condition: NoteConditionGroup(
        combinator: _combinator,
        conditions: List.of(_conditions),
      ),
    );
    widget.chain.replaceAt(widget.index, _current);
  }

  void _pickCombinator(NoteConditionCombinator combinator) {
    setState(() => _combinator = combinator);
    _apply();
  }

  void _addCondition() {
    setState(() {
      // A "mute soft notes" starting point the performer reshapes from here.
      _conditions.add(
        const NoteFieldCondition(
          field: NoteField.velocity,
          comparison: NoteComparison.lessThan,
          threshold: 0.5,
        ),
      );
      _ids.add(_nextId++);
    });
    _apply();
  }

  void _removeCondition(int i) {
    setState(() {
      _conditions.removeAt(i);
      _ids.removeAt(i);
    });
    _apply();
  }

  void _updateCondition(int i, NoteFieldCondition condition) {
    _conditions[i] = condition;
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit mute condition',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EditorRow(
                label: 'mute when',
                child: EditorChoice<NoteConditionCombinator>(
                  value: _combinator,
                  options: [
                    for (final c in NoteConditionCombinator.values)
                      (c, c.label),
                  ],
                  onChanged: _pickCombinator,
                ),
              ),
              if (_conditions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'no conditions — every note plays',
                    style: PhiType.monoS().copyWith(
                      fontSize: 11,
                      color: PhiColors.fg3,
                    ),
                  ),
                ),
              for (var i = 0; i < _conditions.length; i++)
                _ConditionBlock(
                  key: ValueKey(_ids[i]),
                  condition: _conditions[i],
                  onChanged: (c) => _updateCondition(i, c),
                  onRemove: () => _removeCondition(i),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _addCondition,
                  child: const Text('+ add condition'),
                ),
              ),
            ],
          ),
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

/// One leaf condition's editable block: a field picker, a comparison picker, a
/// threshold field, and a remove affordance. Owns its threshold controller;
/// field and comparison are plain enum state, so switching either just re-emits
/// without rebuilding a controller. Emits a rebuilt [NoteFieldCondition] on
/// every change; a threshold that doesn't parse keeps the last good value.
class _ConditionBlock extends StatefulWidget {
  const _ConditionBlock({
    required this.condition,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final NoteFieldCondition condition;
  final ValueChanged<NoteFieldCondition> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ConditionBlock> createState() => _ConditionBlockState();
}

class _ConditionBlockState extends State<_ConditionBlock> {
  late NoteField _field = widget.condition.field;
  late NoteComparison _comparison = widget.condition.comparison;
  late double _lastThreshold = widget.condition.threshold;
  late final TextEditingController _threshold = TextEditingController(
    text: _fmt(widget.condition.threshold),
  );

  static String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  void _pickField(NoteField field) {
    setState(() => _field = field);
    _emit();
  }

  void _pickComparison(NoteComparison comparison) {
    setState(() => _comparison = comparison);
    _emit();
  }

  void _emit() {
    final threshold = double.tryParse(_threshold.text) ?? _lastThreshold;
    _lastThreshold = threshold;
    widget.onChanged(
      NoteFieldCondition(
        field: _field,
        comparison: _comparison,
        threshold: threshold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: EditorChoice<NoteField>(
                  value: _field,
                  options: [for (final f in NoteField.values) (f, f.label)],
                  onChanged: _pickField,
                ),
              ),
              EditorRemoveButton(onRemove: widget.onRemove),
            ],
          ),
          EditorRow(
            label: 'is',
            child: EditorChoice<NoteComparison>(
              value: _comparison,
              options: [for (final c in NoteComparison.values) (c, c.label)],
              onChanged: _pickComparison,
            ),
          ),
          EditorRow(
            label: 'value',
            child: EditorTextInput(
              controller: _threshold,
              onChanged: (_) => _emit(),
            ),
          ),
        ],
      ),
    );
  }
}
