import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/runtime/runtime_variable.dart';
import '../../../domain/runtime/runtime_variable_registry.dart';
import 'runtime_variable_define_dialog.dart';

/// The graph-mode strip that surfaces the performance's [RuntimeVariable]s and
/// lets the performer move them live (issue #78).
///
/// Each variable renders as its name plus a segmented control of its candidate
/// values; tapping a segment sets that value on the shared
/// [RuntimeVariableRegistry] — the same registry the edge-condition picker and
/// the live [GraphEvalContext] read, so flipping a value here opens or closes a
/// `var · name = value` branch on the canvas and in the preview at once. The
/// `+ var` action defines a new variable; the `×` on a chip removes one.
///
/// Listens to the registry itself so it repaints on a define / value change
/// even when used in isolation (widget tests), not only through the viewport's
/// merged listenable.
class RuntimeVariablesBar extends StatelessWidget {
  const RuntimeVariablesBar({required this.registry, super.key});

  final RuntimeVariableRegistry registry;

  Future<void> _define(
    BuildContext context, {
    RuntimeVariable? existing,
  }) async {
    final definition = await showDialog<RuntimeVariableDefinition>(
      context: context,
      builder: (_) => RuntimeVariableDefineDialog(
        initialName: existing?.name ?? '',
        initialValues: existing?.values.join(', ') ?? '',
      ),
    );
    if (definition == null) return;
    registry.define(name: definition.name, values: definition.values);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final variables = registry.variables.toList(growable: false);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: PhiColors.bg1,
            border: Border.all(color: PhiColors.line1),
            borderRadius: PhiRadii.all1,
          ),
          child: Row(
            children: [
              Text(
                'VARS',
                style: PhiType.caption().copyWith(color: PhiColors.fg2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: variables.isEmpty
                    ? Text(
                        'no runtime variables — define one to guard a branch',
                        style: PhiType.monoS().copyWith(
                          fontSize: 11,
                          color: PhiColors.fg2,
                        ),
                      )
                    : Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final v in variables)
                            _VariableChip(
                              variable: v,
                              onSet: (value) =>
                                  registry.setValue(v.name, value),
                              onRemove: () => registry.remove(v.name),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 8),
              _BarAction(label: '+ var', onTap: () => _define(context)),
            ],
          ),
        );
      },
    );
  }
}

/// One variable: its name, a segmented control of its values (current lit), and
/// a remove affordance.
class _VariableChip extends StatelessWidget {
  const _VariableChip({
    required this.variable,
    required this.onSet,
    required this.onRemove,
  });

  final RuntimeVariable variable;
  final void Function(String value) onSet;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${variable.name} ',
          style: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg1),
        ),
        for (final value in variable.values) ...[
          _ValueSegment(
            label: value,
            selected: value == variable.current,
            onTap: () => onSet(value),
          ),
          const SizedBox(width: 2),
        ],
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '×',
              style: PhiType.monoS().copyWith(
                fontSize: 12,
                color: PhiColors.fg2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single candidate value in a variable's segmented control — lit when it is
/// the variable's current value.
class _ValueSegment extends StatelessWidget {
  const _ValueSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? PhiColors.bg2 : null,
          border: Border.all(
            color: selected ? PhiColors.line2 : PhiColors.line1,
          ),
          borderRadius: PhiRadii.all1,
        ),
        child: Text(
          label.toUpperCase(),
          style: PhiType.monoS().copyWith(
            fontSize: 10,
            color: selected ? PhiColors.fg0 : PhiColors.fg2,
          ),
        ),
      ),
    );
  }
}

/// A slim text action button for the bar (`+ var`), matching the mode bar's.
class _BarAction extends StatelessWidget {
  const _BarAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: PhiType.monoS().copyWith(color: PhiColors.fg1),
        ),
      ),
    );
  }
}
