import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/runtime/runtime_variable.dart';
import '../../domain/state_machine/store/state_trigger.dart';

/// A pickable `domain.` clock for a timed trigger — its address plus the
/// authored tempo the picker labels it with.
typedef TriggerDomainOption = ({EntityAddress address, double tempo});

/// The transition **trigger editor** (design `docs/design/state-graph.md` §5,
/// issue #244): kind + params in one small dialog. Opened from the canvas by
/// tapping a transition (or its badge, for non-manual kinds).
///
/// - **manual** / **code** carry no params.
/// - **timed** takes the beat count and the `domain.` clock it counts on,
///   picked from the project's domains.
/// - **variable** takes the watched runtime variable and the value that
///   fires, picked from the live registry's definitions (a stored trigger
///   naming a variable not currently defined stays offered, so editing
///   another field never silently rewrites it).
///
/// [show] resolves to the edited [StateTrigger], or `null` on cancel — the
/// caller (the canvas) writes it through the controller's journaled
/// `setTrigger`.
class StateTriggerEditor extends StatefulWidget {
  const StateTriggerEditor({
    required this.initial,
    required this.domains,
    required this.variables,
    super.key,
  });

  /// The transition's current trigger, seeding every field.
  final StateTrigger initial;

  /// The `domain.` clocks a timed trigger can count on, in registry order.
  final List<TriggerDomainOption> domains;

  /// The runtime variables a variable trigger can watch, in definition order.
  final List<RuntimeVariable> variables;

  static const Key kindKey = Key('StateTriggerEditor.kind');
  static const Key beatsKey = Key('StateTriggerEditor.beats');
  static const Key domainKey = Key('StateTriggerEditor.domain');
  static const Key nameKey = Key('StateTriggerEditor.name');
  static const Key valueKey = Key('StateTriggerEditor.value');
  static const Key saveKey = Key('StateTriggerEditor.save');
  static const Key cancelKey = Key('StateTriggerEditor.cancel');

  /// Show the editor over [context]; resolves to the edited trigger, or
  /// `null` when cancelled (or barrier-dismissed).
  static Future<StateTrigger?> show(
    BuildContext context, {
    required StateTrigger initial,
    required List<TriggerDomainOption> domains,
    required List<RuntimeVariable> variables,
  }) {
    return showDialog<StateTrigger>(
      context: context,
      builder: (_) => StateTriggerEditor(
        initial: initial,
        domains: domains,
        variables: variables,
      ),
    );
  }

  @override
  State<StateTriggerEditor> createState() => _StateTriggerEditorState();
}

class _StateTriggerEditorState extends State<StateTriggerEditor> {
  static const List<String> _kinds = ['manual', 'code', 'timed', 'variable'];

  late String _kind;
  late final TextEditingController _beats;
  EntityAddress? _domain;
  String? _name;
  String? _value;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _kind = initial.kind;
    _beats = TextEditingController(
      text: initial is TimedTrigger ? _formatBeats(initial.beats) : '4',
    );
    _domain = initial is TimedTrigger
        ? initial.domain
        : widget.domains.firstOrNull?.address;
    if (initial is VariableTrigger) {
      _name = initial.name;
      _value = initial.value;
    } else {
      _name = widget.variables.firstOrNull?.name;
      _value = _candidatesFor(_name).firstOrNull;
    }
  }

  @override
  void dispose() {
    _beats.dispose();
    super.dispose();
  }

  /// The value candidates for the variable named [name]: its live definition's
  /// values, keeping a stored value that is no longer a candidate offered.
  List<String> _candidatesFor(String? name) {
    final defined = [
      for (final variable in widget.variables)
        if (variable.name == name) ...variable.values,
    ];
    final initial = widget.initial;
    if (initial is VariableTrigger &&
        initial.name == name &&
        !defined.contains(initial.value)) {
      return [initial.value, ...defined];
    }
    return defined;
  }

  /// The watchable variable names: the live definitions, plus a stored name
  /// not currently defined.
  List<String> get _variableNames {
    final names = [for (final variable in widget.variables) variable.name];
    final initial = widget.initial;
    if (initial is VariableTrigger && !names.contains(initial.name)) {
      return [initial.name, ...names];
    }
    return names;
  }

  double? get _parsedBeats => double.tryParse(_beats.text.trim());

  bool get _valid => switch (_kind) {
    'timed' => (_parsedBeats ?? 0) > 0 && _domain != null,
    'variable' => _name != null && _value != null,
    _ => true,
  };

  StateTrigger _buildTrigger() => switch (_kind) {
    'code' => const CodeTrigger(),
    'timed' => TimedTrigger(beats: _parsedBeats!, domain: _domain!),
    'variable' => VariableTrigger(name: _name!, value: _value!),
    _ => const ManualTrigger(),
  };

  static String _formatBeats(double beats) =>
      beats == beats.roundToDouble() ? '${beats.round()}' : beats.toString();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'trigger',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(label: 'fires', child: _kindPicker()),
            if (_kind == 'timed') ...[
              const SizedBox(height: PhiSpacing.s2),
              _Field(label: 'beats', child: _beatsField()),
              const SizedBox(height: PhiSpacing.s2),
              _Field(label: 'domain', child: _domainPicker()),
            ],
            if (_kind == 'variable') ...[
              const SizedBox(height: PhiSpacing.s2),
              _Field(label: 'variable', child: _namePicker()),
              const SizedBox(height: PhiSpacing.s2),
              _Field(label: 'value', child: _valuePicker()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: StateTriggerEditor.cancelKey,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(
          key: StateTriggerEditor.saveKey,
          onPressed: _valid
              ? () => Navigator.of(context).pop(_buildTrigger())
              : null,
          child: const Text('save'),
        ),
      ],
    );
  }

  Widget _kindPicker() {
    return PhiSelect<String>.flat(
      key: StateTriggerEditor.kindKey,
      value: _kind,
      options: [
        for (final kind in _kinds) PhiSelectOption(value: kind, label: kind),
      ],
      onChanged: (kind) => setState(() => _kind = kind),
    );
  }

  Widget _beatsField() {
    return TextField(
      key: StateTriggerEditor.beatsKey,
      controller: _beats,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: PhiType.body().copyWith(fontSize: 14, color: PhiColors.fg0),
      cursorColor: PhiColors.voice1,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: PhiSpacing.s3,
          vertical: PhiSpacing.s2,
        ),
        filled: true,
        fillColor: PhiColors.bg2,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: PhiColors.line1),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: PhiColors.lineHot),
        ),
      ),
    );
  }

  Widget _domainPicker() {
    final options = [
      for (final domain in widget.domains)
        PhiSelectOption<EntityAddress>(
          value: domain.address,
          label: '${domain.address.name} · ${_formatBeats(domain.tempo)} bpm',
        ),
    ];
    // A stored domain no longer in the project stays offered, so switching
    // kinds back and forth never silently rewrites it.
    final selected = _domain;
    if (selected != null && options.every((o) => o.value != selected)) {
      options.insert(
        0,
        PhiSelectOption<EntityAddress>(
          value: selected,
          label: selected.format(),
        ),
      );
    }
    return PhiSelect<EntityAddress>.flat(
      key: StateTriggerEditor.domainKey,
      value: _domain,
      placeholder: 'no domains',
      options: options,
      onChanged: (domain) => setState(() => _domain = domain),
    );
  }

  Widget _namePicker() {
    return PhiSelect<String>.flat(
      key: StateTriggerEditor.nameKey,
      value: _name,
      placeholder: 'no variables',
      options: [
        for (final name in _variableNames)
          PhiSelectOption(value: name, label: name),
      ],
      onChanged: (name) => setState(() {
        _name = name;
        _value = _candidatesFor(name).firstOrNull;
      }),
    );
  }

  Widget _valuePicker() {
    return PhiSelect<String>.flat(
      key: StateTriggerEditor.valueKey,
      value: _value,
      placeholder: 'no values',
      options: [
        for (final value in _candidatesFor(_name))
          PhiSelectOption(value: value, label: value),
      ],
      onChanged: (value) => setState(() => _value = value),
    );
  }
}

/// One labelled row: a dim caption on the left, the control on the right —
/// the metronome popover's field shape.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label.toUpperCase(),
            style: PhiType.monoS().copyWith(
              color: PhiColors.fg3,
              fontSize: 9,
              letterSpacing: 0.08 * 9,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
