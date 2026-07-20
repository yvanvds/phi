import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/synth/fm_bank_reader.dart';
import '../../domain/synth/fm_synth.dart';
import '../../domain/synth/sampler_synth.dart';
import '../../domain/synth/sine_synth.dart';
import '../../domain/synth/synth_kind.dart';
import '../../domain/synth/va_synth.dart';
import '../../engine/state/rack_definitions_controller.dart';
import 'editors/fm_synth_editor.dart';
import 'editors/fx_editor.dart';
import 'editors/sampler_synth_editor.dart';
import 'editors/sine_synth_editor.dart';
import 'editors/va_synth_editor.dart';
import 'rack_asset_source.dart';

/// The racks surface's center **editor pane** (design
/// `docs/design/racks-and-voices.md` §8) — where the selected definition's panel
/// lives.
///
/// The pane binds to the [RackDefinitionsController] selection, renders a titled
/// header (the definition's name + its `namespace · kind` tag), and dispatches
/// the body to the per-kind editor (issue #210): the VA sectioned panel, the FM
/// bank + patch browser, the sampler picker, or the fx param rows. Nothing
/// selected shows the empty hint. The FM / sampler editors reach the injected
/// [RackAssetSource] (asset import) and [FmBankReader] (patch browsing).
class DefinitionEditorPane extends StatelessWidget {
  const DefinitionEditorPane({
    required this.controller,
    this.assetSource,
    this.bankReader,
    super.key,
  });

  final RackDefinitionsController controller;
  final RackAssetSource? assetSource;
  final FmBankReader? bankReader;

  /// Key on the pane's title text — carries the selected definition's name, so a
  /// test can assert selection drives the editor.
  static const Key titleKey = Key('DefinitionEditorPane.title');

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
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(selected.format()),
                    child: _editorFor(selected),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _editorFor(EntityAddress selected) {
    if (selected.kind == RegistryKinds.synth) {
      final definition = controller.synthAt(selected);
      if (definition == null) return _unreadable();
      switch (definition.kind) {
        case SynthKind.sine:
          return SineSynthEditor(
            controller: controller,
            address: selected,
            definition: definition as SineSynth,
          );
        case SynthKind.va:
          return VaSynthEditor(
            controller: controller,
            address: selected,
            definition: definition as VaSynth,
          );
        case SynthKind.fm:
          return FmSynthEditor(
            controller: controller,
            address: selected,
            definition: definition as FmSynth,
            assetSource: assetSource,
            bankReader: bankReader,
          );
        case SynthKind.sampler:
          return SamplerSynthEditor(
            controller: controller,
            address: selected,
            definition: definition as SamplerSynth,
            assetSource: assetSource,
          );
      }
    }
    final definition = controller.fxAt(selected);
    if (definition == null) return _unreadable();
    return FxEditor(
      controller: controller,
      address: selected,
      definition: definition,
    );
  }

  Widget _unreadable() => Center(
    child: Text(
      'this definition could not be read',
      style: PhiType.monoS().copyWith(color: PhiColors.fg3),
    ),
  );
}
