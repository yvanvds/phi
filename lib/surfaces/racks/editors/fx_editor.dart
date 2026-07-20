import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/fx/fx_definition.dart';
import '../../../domain/fx/fx_kind.dart';
import '../../../domain/project/entity_address.dart';
import '../../../engine/state/rack_definitions_controller.dart';
import 'editor_section.dart';
import 'editor_slider_row.dart';
import 'editor_toggle_row.dart';
import 'fx_param_spec.dart';

/// The fx editor panel — one labelled row per param, per kind (design
/// `docs/design/racks-and-voices.md` §5, §8).
///
/// Two universal controls (`impact` wet/dry, `bypass`) sit above the kind's own
/// params ([fxParamsFor]). A param absent from the payload shows its spec
/// default and writes on first touch; sliders coalesce their drag. Every edit
/// commits through [RackDefinitionsController.updateFx] as one journaled payload
/// command.
class FxEditor extends StatelessWidget {
  const FxEditor({
    required this.controller,
    required this.address,
    required this.definition,
    super.key,
  });

  final RackDefinitionsController controller;
  final EntityAddress address;
  final FxDefinition definition;

  double _valueOf(FxParamSpec spec) =>
      definition.params[spec.name] ?? spec.defaultValue;

  void _setParam(String name, double value) =>
      controller.updateFx(address, definition.withParam(name, value));

  @override
  Widget build(BuildContext context) {
    final specs = fxParamsFor(definition.kind);
    if (definition.kind == FxKind.patcherInsert) {
      return EditorSection(
        title: 'patcher insert',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'reserved — params arrive with the patcher epic',
              style: PhiType.monoS().copyWith(color: PhiColors.fg3),
            ),
          ),
        ],
      );
    }
    return ListView(
      children: [
        EditorSection(
          title: 'mix',
          children: [
            EditorSliderRow(
              label: 'impact',
              value: definition.params['impact'] ?? 1.0,
              min: 0,
              max: 1,
              onCommit: (v) => _setParam('impact', v),
            ),
            EditorToggleRow(
              label: 'bypass',
              value: (definition.params['bypass'] ?? 0) != 0,
              onChanged: (on) => _setParam('bypass', on ? 1 : 0),
            ),
          ],
        ),
        if (specs.isNotEmpty)
          EditorSection(
            title: definition.kind.name,
            children: [
              for (final spec in specs)
                EditorSliderRow(
                  label: spec.label,
                  value: _valueOf(spec),
                  min: spec.min,
                  max: spec.max,
                  asInt: spec.isInt,
                  onCommit: (v) => _setParam(spec.name, v),
                ),
            ],
          ),
      ],
    );
  }
}
