import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/project/registry_kinds.dart';
import '../../engine/state/rack_definitions_controller.dart';

/// The racks surface's center **editor pane** (issue #209, design
/// `docs/design/racks-and-voices.md` §8) — where the selected definition's panel
/// lives.
///
/// This issue lands the *plumbing*: the pane binds to the
/// [RackDefinitionsController] selection and routes to the right target, but the
/// per-kind panels (VA sliders, FM bank + patch browser, sampler picker, fx param
/// rows) arrive in #212. Until then it shows a titled placeholder naming the
/// selected definition and its kind, or an empty hint when nothing is selected —
/// enough for the selection → editor routing to be observable end-to-end.
class DefinitionEditorPane extends StatelessWidget {
  const DefinitionEditorPane({required this.controller, super.key});

  final RackDefinitionsController controller;

  /// Key on the pane's title text — carries the selected address (or a sentinel
  /// when empty), so a test can assert selection drives the editor.
  static const Key titleKey = Key('DefinitionEditorPane.title');

  /// Key shown only when a definition is selected — its placeholder body.
  static const Key placeholderKey = Key('DefinitionEditorPane.placeholder');

  /// Key shown only when nothing is selected — the empty hint.
  static const Key emptyKey = Key('DefinitionEditorPane.empty');

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final selected = controller.selected;
          if (selected == null) {
            return const Center(
              child: Text(
                'select a definition to edit',
                key: DefinitionEditorPane.emptyKey,
                style: TextStyle(color: PhiColors.fg3),
              ),
            );
          }
          final tag = controller.kindTagAt(selected);
          final namespace = selected.kind == RegistryKinds.synth
              ? 'synth'
              : 'effect';
          return Padding(
            padding: const EdgeInsets.all(PhiSpacing.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.name,
                  key: DefinitionEditorPane.titleKey,
                  style: PhiType.h3().copyWith(color: PhiColors.fg0),
                ),
                const SizedBox(height: PhiSpacing.s1),
                Text(
                  tag == null ? namespace : '$namespace · $tag',
                  style: PhiType.monoS().copyWith(color: PhiColors.fg2),
                ),
                const SizedBox(height: PhiSpacing.s4),
                Container(
                  key: DefinitionEditorPane.placeholderKey,
                  padding: const EdgeInsets.all(PhiSpacing.s4),
                  decoration: BoxDecoration(
                    color: PhiColors.bg1,
                    borderRadius: PhiRadii.all2,
                    border: Border.all(color: PhiColors.line1),
                  ),
                  child: Text(
                    'parameter editor coming soon',
                    style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
