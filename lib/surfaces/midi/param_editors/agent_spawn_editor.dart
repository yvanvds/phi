import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/midi/midi_transform_chain.dart';
import '../../../domain/midi/spawn_axis.dart';
import '../../../domain/midi/spawn_source.dart';
import '../../../domain/midi/transforms/agent_spawn_transform.dart';
import 'editor_fields.dart';

/// Typed editor for an [AgentSpawnTransform] (issue #95): the three position
/// axes plus the constant drift.
///
/// Each of x/y/z is a [SpawnAxis] — a note dimension (pitch/time/velocity/
/// channel) linearly remapped from an input domain `[in, in]` onto a spatial
/// range `[out, out]`. The drift is a constant scene-units/second velocity
/// stamped on every spawn. Everything applies **live** through
/// [MidiTransformChain.replaceAt]; a field that doesn't parse keeps the axis's
/// last valid number.
class AgentSpawnEditor extends StatefulWidget {
  const AgentSpawnEditor({required this.chain, required this.index, super.key});

  final MidiTransformChain chain;
  final int index;

  @override
  State<AgentSpawnEditor> createState() => _AgentSpawnEditorState();
}

class _AgentSpawnEditorState extends State<AgentSpawnEditor> {
  late AgentSpawnTransform _current =
      widget.chain.transforms[widget.index] as AgentSpawnTransform;

  late final List<_AxisCtrl> _axes = [
    _AxisCtrl.of(_current.x),
    _AxisCtrl.of(_current.y),
    _AxisCtrl.of(_current.z),
  ];
  late final List<SpawnSource> _sources = [
    _current.x.source,
    _current.y.source,
    _current.z.source,
  ];
  late final List<TextEditingController> _drift = [
    TextEditingController(text: _fmt(_current.velocity.x)),
    TextEditingController(text: _fmt(_current.velocity.y)),
    TextEditingController(text: _fmt(_current.velocity.z)),
  ];

  static const _axisLabels = ['x', 'y', 'z'];
  static const _sourceOptions = <(SpawnSource, String)>[
    (SpawnSource.pitch, 'pitch'),
    (SpawnSource.time, 'time'),
    (SpawnSource.velocity, 'velocity'),
    (SpawnSource.channel, 'channel'),
  ];

  static String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    for (final axis in _axes) {
      axis.dispose();
    }
    for (final c in _drift) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    if (widget.index >= widget.chain.transforms.length) return;
    final fallback = [_current.x, _current.y, _current.z];
    _current = _current.copyWith(
      x: _axes[0].toAxis(_sources[0], fallback[0]),
      y: _axes[1].toAxis(_sources[1], fallback[1]),
      z: _axes[2].toAxis(_sources[2], fallback[2]),
      velocity: Vector3(
        double.tryParse(_drift[0].text) ?? _current.velocity.x,
        double.tryParse(_drift[1].text) ?? _current.velocity.y,
        double.tryParse(_drift[2].text) ?? _current.velocity.z,
      ),
    );
    widget.chain.replaceAt(widget.index, _current);
  }

  void _pickSource(int axis, SpawnSource source) {
    setState(() => _sources[axis] = source);
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'edit spawn',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < 3; i++) ...[
                _SectionLabel(text: 'axis ${_axisLabels[i]}'),
                EditorRow(
                  label: 'source',
                  child: EditorChoice<SpawnSource>(
                    value: _sources[i],
                    options: _sourceOptions,
                    onChanged: (s) => _pickSource(i, s),
                  ),
                ),
                _AxisFields(ctrl: _axes[i], onChanged: _apply),
              ],
              const _SectionLabel(text: 'drift · units/sec'),
              for (var i = 0; i < 3; i++)
                EditorRow(
                  label: _axisLabels[i],
                  child: EditorTextInput(
                    controller: _drift[i],
                    onChanged: (_) => _apply(),
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

/// The four range controllers backing one [SpawnAxis].
class _AxisCtrl {
  _AxisCtrl.of(SpawnAxis axis)
    : inMin = TextEditingController(
        text: _AgentSpawnEditorState._fmt(axis.inMin),
      ),
      inMax = TextEditingController(
        text: _AgentSpawnEditorState._fmt(axis.inMax),
      ),
      outMin = TextEditingController(
        text: _AgentSpawnEditorState._fmt(axis.outMin),
      ),
      outMax = TextEditingController(
        text: _AgentSpawnEditorState._fmt(axis.outMax),
      );

  final TextEditingController inMin;
  final TextEditingController inMax;
  final TextEditingController outMin;
  final TextEditingController outMax;

  /// The [SpawnAxis] this row currently describes, for [source]. A field that
  /// doesn't parse keeps the matching value from [fallback].
  SpawnAxis toAxis(SpawnSource source, SpawnAxis fallback) => SpawnAxis(
    source: source,
    inMin: double.tryParse(inMin.text) ?? fallback.inMin,
    inMax: double.tryParse(inMax.text) ?? fallback.inMax,
    outMin: double.tryParse(outMin.text) ?? fallback.outMin,
    outMax: double.tryParse(outMax.text) ?? fallback.outMax,
  );

  void dispose() {
    inMin.dispose();
    inMax.dispose();
    outMin.dispose();
    outMax.dispose();
  }
}

/// The `in → out` range grid for one axis: two rows of paired fields.
class _AxisFields extends StatelessWidget {
  const _AxisFields({required this.ctrl, required this.onChanged});

  final _AxisCtrl ctrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EditorRow(
          label: 'input',
          childWidth: 150,
          child: _Pair(a: ctrl.inMin, b: ctrl.inMax, onChanged: onChanged),
        ),
        EditorRow(
          label: 'output',
          childWidth: 150,
          child: _Pair(a: ctrl.outMin, b: ctrl.outMax, onChanged: onChanged),
        ),
      ],
    );
  }
}

/// Two fields separated by an en dash — a `[min, max]` range.
class _Pair extends StatelessWidget {
  const _Pair({required this.a, required this.b, required this.onChanged});

  final TextEditingController a;
  final TextEditingController b;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: EditorTextInput(controller: a, onChanged: (_) => onChanged()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '–',
            style: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg3),
          ),
        ),
        Expanded(
          child: EditorTextInput(controller: b, onChanged: (_) => onChanged()),
        ),
      ],
    );
  }
}

/// A dim sub-header separating an editor's sections.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: PhiType.monoS().copyWith(
          fontSize: 8,
          color: PhiColors.fg3,
          letterSpacing: 0.08 * 8,
        ),
      ),
    );
  }
}
