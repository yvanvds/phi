import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/synth/sample_recipe.dart';
import '../../../domain/synth/sampler_synth.dart';
import '../../../engine/state/rack_definitions_controller.dart';
import '../rack_asset_source.dart';
import 'editor_choice_row.dart';
import 'editor_number_row.dart';
import 'editor_section.dart';
import 'editor_slider_row.dart';

/// The sampler editor panel (design `docs/design/racks-and-voices.md` §4, §8):
/// an SFZ instrument picker **or** a single-sample recipe (file, root, range,
/// attack/release), plus voice count.
///
/// The two sources are mutually exclusive — a `source` picker flips between
/// them, clearing the other (mirroring [SamplerSynth]'s invariant). Files are
/// imported into the project's `assets/` through the [RackAssetSource]; every
/// edit commits through [RackDefinitionsController.updateSynth] as one journaled
/// payload command.
class SamplerSynthEditor extends StatelessWidget {
  const SamplerSynthEditor({
    required this.controller,
    required this.address,
    required this.definition,
    this.assetSource,
    super.key,
  });

  final RackDefinitionsController controller;
  final EntityAddress address;
  final SamplerSynth definition;
  final RackAssetSource? assetSource;

  /// Key on the "load .sfz" button.
  static const Key loadSfzKey = Key('SamplerSynthEditor.loadSfz');

  /// Key on the "load sample" button.
  static const Key loadSampleKey = Key('SamplerSynthEditor.loadSample');

  bool get _isSfz => definition.sfzAsset != null;

  void _commit(SamplerSynth next) => controller.updateSynth(address, next);

  Future<void> _loadSfz() async {
    final ref = await assetSource?.pickAsset(RackAssetKind.sfz);
    if (ref == null) return;
    _commit(definition.withSfz(ref));
  }

  Future<void> _loadSample() async {
    final ref = await assetSource?.pickAsset(RackAssetKind.sample);
    if (ref == null) return;
    final recipe = definition.recipe;
    _commit(
      definition.withRecipe(
        recipe == null ? SampleRecipe(file: ref) : recipe.copyWith(file: ref),
      ),
    );
  }

  void _setRecipe(SampleRecipe recipe) =>
      _commit(definition.withRecipe(recipe));

  void _switchSource(String mode) {
    if (mode == 'sfz' && !_isSfz) {
      _commit(
        SamplerSynth(
          sfzAsset: definition.sfzAsset,
          voiceCount: definition.voiceCount,
        ),
      );
    } else if (mode == 'sample' && _isSfz) {
      _commit(
        SamplerSynth(
          recipe: definition.recipe,
          voiceCount: definition.voiceCount,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        EditorSection(
          title: 'source',
          children: [
            EditorChoiceRow<String>(
              label: 'type',
              value: _isSfz ? 'sfz' : 'sample',
              options: const [
                ('sfz', 'sfz instrument'),
                ('sample', 'single sample'),
              ],
              onChanged: _switchSource,
            ),
            if (_isSfz) ..._sfzFields() else ..._sampleFields(),
          ],
        ),
        EditorSection(
          title: 'output',
          children: [
            EditorNumberRow(
              label: 'voice count',
              value: definition.voiceCount,
              min: 1,
              max: 64,
              onCommit: (v) => _commit(
                _isSfz
                    ? SamplerSynth(sfzAsset: definition.sfzAsset, voiceCount: v)
                    : SamplerSynth(recipe: definition.recipe, voiceCount: v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _sfzFields() => [
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        definition.sfzAsset ?? 'no instrument loaded',
        style: PhiType.monoS().copyWith(color: PhiColors.fg2),
      ),
    ),
    _FileButton(
      buttonKey: SamplerSynthEditor.loadSfzKey,
      label: 'load .sfz…',
      enabled: assetSource != null,
      onTap: _loadSfz,
    ),
  ];

  List<Widget> _sampleFields() {
    final recipe = definition.recipe;
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          recipe?.file ?? 'no sample loaded',
          style: PhiType.monoS().copyWith(color: PhiColors.fg2),
        ),
      ),
      _FileButton(
        buttonKey: SamplerSynthEditor.loadSampleKey,
        label: 'load sample…',
        enabled: assetSource != null,
        onTap: _loadSample,
      ),
      if (recipe != null) ...[
        EditorNumberRow(
          label: 'root',
          value: recipe.root,
          min: 0,
          max: 127,
          onCommit: (v) => _setRecipe(recipe.copyWith(root: v)),
        ),
        EditorNumberRow(
          label: 'low',
          value: recipe.low,
          min: 0,
          max: 127,
          onCommit: (v) => _setRecipe(recipe.copyWith(low: v)),
        ),
        EditorNumberRow(
          label: 'high',
          value: recipe.high,
          min: 0,
          max: 127,
          onCommit: (v) => _setRecipe(recipe.copyWith(high: v)),
        ),
        EditorSliderRow(
          label: 'attack',
          value: recipe.attack,
          min: 0,
          max: 4,
          onCommit: (v) => _setRecipe(recipe.copyWith(attack: v)),
        ),
        EditorSliderRow(
          label: 'release',
          value: recipe.release,
          min: 0,
          max: 4,
          onCommit: (v) => _setRecipe(recipe.copyWith(release: v)),
        ),
      ],
    ];
  }
}

/// A labelled file-picker button, disabled when no asset source is wired.
class _FileButton extends StatelessWidget {
  const _FileButton({
    required this.buttonKey,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final Key buttonKey;
  final String label;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => unawaited(onTap()) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s2,
            vertical: PhiSpacing.s1,
          ),
          decoration: BoxDecoration(
            color: PhiColors.bg2,
            borderRadius: PhiRadii.all1,
            border: Border.all(color: PhiColors.line1),
          ),
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              color: enabled ? PhiColors.fg0 : PhiColors.fg3,
            ),
          ),
        ),
      ),
    );
  }
}
