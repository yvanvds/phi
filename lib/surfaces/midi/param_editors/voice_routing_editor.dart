import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/music_scale.dart';
import '../../../domain/midi/transforms/voice_routing_rule.dart';
import '../../../domain/midi/transforms/voice_routing_transform.dart';
import 'editor_fields.dart';

/// Typed editor for a [VoiceRoutingTransform] (issue #95): the ordered list of
/// [VoiceRoutingRule]s, first-match-wins.
///
/// Each rule picks its kind (pitch range · velocity range · scale degree),
/// spells out that kind's fields, and names the channel it routes matches to.
/// Rules apply in list order, so specific rules go above catch-alls. Every
/// edit applies **live** through [MidiTransformChain.replaceAt]; an empty list
/// leaves every note on its incoming channel.
class VoiceRoutingEditor extends StatefulWidget {
  const VoiceRoutingEditor({
    required this.chain,
    required this.index,
    super.key,
  });

  final MidiTransformChain chain;
  final int index;

  @override
  State<VoiceRoutingEditor> createState() => _VoiceRoutingEditorState();
}

class _VoiceRoutingEditorState extends State<VoiceRoutingEditor> {
  late VoiceRoutingTransform _current =
      widget.chain.transforms[widget.index] as VoiceRoutingTransform;

  late final List<VoiceRoutingRule> _rules = [..._current.rules];
  // Stable ids so a removed rule doesn't shuffle sibling row state.
  late final List<int> _ids = [for (var i = 0; i < _rules.length; i++) i];
  late int _nextId = _rules.length;

  void _apply() {
    if (widget.index >= widget.chain.transforms.length) return;
    _current = _current.copyWith(rules: List.of(_rules));
    widget.chain.replaceAt(widget.index, _current);
  }

  void _addRule() {
    setState(() {
      _rules.add(const PitchRangeRule(minPitch: 0, maxPitch: 127, channel: 1));
      _ids.add(_nextId++);
    });
    _apply();
  }

  void _removeRule(int i) {
    setState(() {
      _rules.removeAt(i);
      _ids.removeAt(i);
    });
    _apply();
  }

  void _updateRule(int i, VoiceRoutingRule rule) {
    _rules[i] = rule;
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit routing',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'no rules — every note keeps its channel',
                    style: PhiType.monoS().copyWith(
                      fontSize: 11,
                      color: PhiColors.fg3,
                    ),
                  ),
                ),
              for (var i = 0; i < _rules.length; i++)
                _RuleBlock(
                  key: ValueKey(_ids[i]),
                  rule: _rules[i],
                  onChanged: (r) => _updateRule(i, r),
                  onRemove: () => _removeRule(i),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _addRule,
                  child: const Text('+ add rule'),
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

/// The three routing-rule kinds, for the per-rule kind picker.
enum _RuleKind {
  pitchRange('pitch range'),
  velocityRange('velocity range'),
  scaleDegree('scale degree');

  const _RuleKind(this.label);

  final String label;

  static _RuleKind of(VoiceRoutingRule rule) => switch (rule) {
    PitchRangeRule() => _RuleKind.pitchRange,
    VelocityRangeRule() => _RuleKind.velocityRange,
    ScaleDegreeRule() => _RuleKind.scaleDegree,
  };
}

/// One rule's editable block: a kind picker, that kind's fields, a channel, and
/// a remove affordance. Owns its own controllers so switching kinds rebuilds
/// only this rule's fields; emits a rebuilt [VoiceRoutingRule] on every change.
class _RuleBlock extends StatefulWidget {
  const _RuleBlock({
    required this.rule,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final VoiceRoutingRule rule;
  final ValueChanged<VoiceRoutingRule> onChanged;
  final VoidCallback onRemove;

  @override
  State<_RuleBlock> createState() => _RuleBlockState();
}

class _RuleBlockState extends State<_RuleBlock> {
  late _RuleKind _kind = _RuleKind.of(widget.rule);
  late VoiceRoutingRule _rule = widget.rule;
  late MusicScale _scale = _initialScale;

  // Kind-specific fields, rebuilt on a kind switch. The channel persists
  // across kinds — it means the same thing for every rule.
  late final TextEditingController _channel = TextEditingController(
    text: '${widget.rule.channel}',
  );
  late Map<String, TextEditingController> _fields = _fieldsFor(widget.rule);

  MusicScale get _initialScale => widget.rule is ScaleDegreeRule
      ? (widget.rule as ScaleDegreeRule).scale
      : MusicScale.ionian;

  @override
  void dispose() {
    _channel.dispose();
    _disposeFields();
    super.dispose();
  }

  void _disposeFields() {
    for (final c in _fields.values) {
      c.dispose();
    }
  }

  /// Fresh controllers seeded from [rule]'s kind-specific fields.
  Map<String, TextEditingController> _fieldsFor(VoiceRoutingRule rule) =>
      switch (rule) {
        PitchRangeRule(:final minPitch, :final maxPitch) => {
          'min': TextEditingController(text: '$minPitch'),
          'max': TextEditingController(text: '$maxPitch'),
        },
        VelocityRangeRule(:final minVelocity, :final maxVelocity) => {
          'min': TextEditingController(text: _fmt(minVelocity)),
          'max': TextEditingController(text: _fmt(maxVelocity)),
        },
        ScaleDegreeRule(:final tonic, :final degrees) => {
          'tonic': TextEditingController(text: '$tonic'),
          'degrees': TextEditingController(
            text: (degrees.toList()..sort()).join(', '),
          ),
        },
      };

  static String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  void _switchKind(_RuleKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _disposeFields();
      _fields = _fieldsFor(_defaultFor(kind));
    });
    _emit();
  }

  /// A sensible default rule of [kind], reusing the current channel.
  VoiceRoutingRule _defaultFor(_RuleKind kind) {
    final channel = int.tryParse(_channel.text) ?? 0;
    return switch (kind) {
      _RuleKind.pitchRange => PitchRangeRule(
        minPitch: 0,
        maxPitch: 127,
        channel: channel,
      ),
      _RuleKind.velocityRange => VelocityRangeRule(
        minVelocity: 0,
        maxVelocity: 1,
        channel: channel,
      ),
      _RuleKind.scaleDegree => ScaleDegreeRule(
        scale: _scale,
        tonic: 60,
        degrees: const {1},
        channel: channel,
      ),
    };
  }

  /// Builds the rule from the live controllers and reports it upward. A field
  /// that doesn't parse keeps its value from the last good [_rule].
  void _emit() {
    final channel = int.tryParse(_channel.text) ?? _rule.channel;
    final rule = switch (_kind) {
      _RuleKind.pitchRange => PitchRangeRule(
        minPitch: int.tryParse(_fields['min']!.text) ?? _fallbackInt('min', 0),
        maxPitch:
            int.tryParse(_fields['max']!.text) ?? _fallbackInt('max', 127),
        channel: channel,
      ),
      _RuleKind.velocityRange => VelocityRangeRule(
        minVelocity:
            double.tryParse(_fields['min']!.text) ?? _fallbackDouble('min', 0),
        maxVelocity:
            double.tryParse(_fields['max']!.text) ?? _fallbackDouble('max', 1),
        channel: channel,
      ),
      _RuleKind.scaleDegree => ScaleDegreeRule(
        scale: _scale,
        tonic:
            int.tryParse(_fields['tonic']!.text) ?? _fallbackInt('tonic', 60),
        degrees: _parseDegrees(_fields['degrees']!.text),
        channel: channel,
      ),
    };
    _rule = rule;
    widget.onChanged(rule);
  }

  int _fallbackInt(String field, int orElse) {
    final r = _rule;
    return switch (field) {
      'min' when r is PitchRangeRule => r.minPitch,
      'max' when r is PitchRangeRule => r.maxPitch,
      'tonic' when r is ScaleDegreeRule => r.tonic,
      _ => orElse,
    };
  }

  double _fallbackDouble(String field, double orElse) {
    final r = _rule;
    return switch (field) {
      'min' when r is VelocityRangeRule => r.minVelocity,
      'max' when r is VelocityRangeRule => r.maxVelocity,
      _ => orElse,
    };
  }

  /// Parses a comma-separated degree list into a 1-based set, dropping blanks
  /// and non-numbers so a half-typed field never throws.
  static Set<int> _parseDegrees(String raw) => {
    for (final part in raw.split(',')) ?int.tryParse(part.trim()),
  };

  void _pickScale(MusicScale scale) {
    setState(() => _scale = scale);
    _emit();
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
                child: EditorChoice<_RuleKind>(
                  value: _kind,
                  options: [for (final k in _RuleKind.values) (k, k.label)],
                  onChanged: _switchKind,
                ),
              ),
              EditorRemoveButton(onRemove: widget.onRemove),
            ],
          ),
          ..._kindFields(),
          EditorRow(
            label: 'channel',
            child: EditorTextInput(
              controller: _channel,
              onChanged: (_) => _emit(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _kindFields() => switch (_kind) {
    _RuleKind.pitchRange || _RuleKind.velocityRange => [
      EditorRow(
        label: 'min',
        child: EditorTextInput(
          controller: _fields['min']!,
          onChanged: (_) => _emit(),
        ),
      ),
      EditorRow(
        label: 'max',
        child: EditorTextInput(
          controller: _fields['max']!,
          onChanged: (_) => _emit(),
        ),
      ),
    ],
    _RuleKind.scaleDegree => [
      EditorRow(
        label: 'scale',
        child: EditorChoice<MusicScale>(
          value: _scale,
          options: [for (final s in MusicScale.values) (s, s.label)],
          onChanged: _pickScale,
        ),
      ),
      EditorRow(
        label: 'tonic',
        child: EditorTextInput(
          controller: _fields['tonic']!,
          onChanged: (_) => _emit(),
        ),
      ),
      EditorRow(
        label: 'degrees',
        child: EditorTextInput(
          controller: _fields['degrees']!,
          onChanged: (_) => _emit(),
          hintText: '1, 5',
        ),
      ),
    ],
  };
}
