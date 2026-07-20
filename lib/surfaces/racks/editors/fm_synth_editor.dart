import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../domain/project/entity_address.dart';
import '../../../domain/synth/fm_bank_reader.dart';
import '../../../domain/synth/fm_operator.dart';
import '../../../domain/synth/fm_synth.dart';
import '../../../engine/state/rack_definitions_controller.dart';
import '../rack_asset_source.dart';
import 'editor_number_row.dart';
import 'editor_section.dart';
import 'editor_slider_row.dart';
import 'editor_toggle_row.dart';

/// The FM editor panel — a DX7-class 6-operator voice (design
/// `docs/design/racks-and-voices.md` §4, §8): a bank file picker, the patch list
/// browsed from the bank's `patchCount`/`patchName`, the algorithm / feedback /
/// transpose overrides, and the per-operator grid.
///
/// The bank picker imports a `.syx` into the project's `assets/` via the
/// [RackAssetSource]; the patch browser lists names through the [FmBankReader]
/// (both injected, so tests drive the flow with fakes — the "FM patch browser
/// populating from a fake bank" the issue's *Done when* calls for). Every edit
/// commits through [RackDefinitionsController.updateSynth] as one journaled
/// payload command.
class FmSynthEditor extends StatelessWidget {
  const FmSynthEditor({
    required this.controller,
    required this.address,
    required this.definition,
    this.assetSource,
    this.bankReader,
    super.key,
  });

  final RackDefinitionsController controller;
  final EntityAddress address;
  final FmSynth definition;
  final RackAssetSource? assetSource;
  final FmBankReader? bankReader;

  /// Key on the "load bank" button.
  static const Key loadBankKey = Key('FmSynthEditor.loadBank');

  /// Key on a patch-list row, by index — so a test can find and tap a patch.
  static Key patchRowKey(int index) => Key('FmSynthEditor.patch.$index');

  void _commit(FmSynth next) => controller.updateSynth(address, next);

  Future<void> _loadBank() async {
    final source = assetSource;
    if (source == null) return;
    final ref = await source.pickAsset(RackAssetKind.fmBank);
    if (ref == null) return;
    _commit(definition.copyWith(bankAsset: ref, patchIndex: 0));
  }

  FmOperator _opAt(int index) => definition.operators.firstWhere(
    (o) => o.op == index,
    orElse: () => FmOperator(op: index),
  );

  void _setOp(FmOperator op) {
    final next = [...definition.operators.where((o) => o.op != op.op), op]
      ..sort((a, b) => a.op.compareTo(b.op));
    _commit(definition.copyWith(operators: next));
  }

  @override
  Widget build(BuildContext context) {
    final names =
        bankReader?.patchNames(definition.bankAsset) ?? const <String>[];
    return ListView(
      children: [
        EditorSection(
          title: 'bank',
          trailing: _LoadBankButton(
            enabled: assetSource != null,
            onTap: _loadBank,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                definition.bankAsset ?? 'built-in patch',
                style: PhiType.monoS().copyWith(color: PhiColors.fg2),
              ),
            ),
            _PatchList(
              names: names,
              selected: definition.patchIndex,
              onSelect: (i) => _commit(definition.copyWith(patchIndex: i)),
            ),
          ],
        ),
        EditorSection(
          title: 'globals',
          children: [
            EditorSliderRow(
              label: 'algorithm',
              value: (definition.algorithm ?? 0).toDouble(),
              min: 0,
              max: 31,
              asInt: true,
              onCommit: (v) =>
                  _commit(definition.copyWith(algorithm: v.round())),
            ),
            EditorSliderRow(
              label: 'feedback',
              value: (definition.feedback ?? 0).toDouble(),
              min: 0,
              max: 7,
              asInt: true,
              onCommit: (v) =>
                  _commit(definition.copyWith(feedback: v.round())),
            ),
            EditorSliderRow(
              label: 'transpose',
              value: (definition.transpose ?? 0).toDouble(),
              min: -24,
              max: 24,
              asInt: true,
              onCommit: (v) =>
                  _commit(definition.copyWith(transpose: v.round())),
            ),
            EditorNumberRow(
              label: 'voice count',
              value: definition.voiceCount,
              min: 1,
              max: 64,
              onCommit: (v) => _commit(definition.copyWith(voiceCount: v)),
            ),
          ],
        ),
        for (var i = 0; i < 6; i++) _opSection(i),
      ],
    );
  }

  Widget _opSection(int index) {
    final op = _opAt(index);
    return EditorSection(
      title: 'operator ${index + 1}',
      children: [
        EditorToggleRow(
          label: 'enabled',
          value: op.enabled,
          onChanged: (v) => _setOp(op.copyWith(enabled: v)),
        ),
        EditorSliderRow(
          label: 'level',
          value: op.outputLevel.toDouble(),
          min: 0,
          max: 99,
          asInt: true,
          onCommit: (v) => _setOp(op.copyWith(outputLevel: v.round())),
        ),
        EditorSliderRow(
          label: 'coarse',
          value: op.freqCoarse.toDouble(),
          min: 0,
          max: 31,
          asInt: true,
          onCommit: (v) => _setOp(op.copyWith(freqCoarse: v.round())),
        ),
        EditorSliderRow(
          label: 'fine',
          value: op.freqFine.toDouble(),
          min: 0,
          max: 99,
          asInt: true,
          onCommit: (v) => _setOp(op.copyWith(freqFine: v.round())),
        ),
        EditorSliderRow(
          label: 'detune',
          value: op.detune.toDouble(),
          min: 0,
          max: 14,
          asInt: true,
          onCommit: (v) => _setOp(op.copyWith(detune: v.round())),
        ),
      ],
    );
  }
}

/// The header "load bank" button — enabled only when an asset source is wired.
class _LoadBankButton extends StatelessWidget {
  const _LoadBankButton({required this.enabled, required this.onTap});

  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: FmSynthEditor.loadBankKey,
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => unawaited(onTap()) : null,
      child: Container(
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
          'load bank…',
          style: PhiType.monoS().copyWith(
            color: enabled ? PhiColors.fg0 : PhiColors.fg3,
          ),
        ),
      ),
    );
  }
}

/// The scrollable list of patch names read from the loaded bank; an empty bank
/// shows a hint. The current [selected] patch is highlighted.
class _PatchList extends StatelessWidget {
  const _PatchList({
    required this.names,
    required this.selected,
    required this.onSelect,
  });

  final List<String> names;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'no bank loaded — load a .syx bank',
          style: PhiType.monoS().copyWith(color: PhiColors.fg3),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.only(top: PhiSpacing.s1),
      decoration: BoxDecoration(
        color: PhiColors.bg0,
        borderRadius: PhiRadii.all1,
        border: Border.all(color: PhiColors.line1),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: names.length,
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          return GestureDetector(
            key: FmSynthEditor.patchRowKey(i),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PhiSpacing.s2,
                vertical: PhiSpacing.s1,
              ),
              color: isSelected ? PhiColors.bg3 : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}',
                      style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      names[i],
                      overflow: TextOverflow.ellipsis,
                      style: PhiType.monoS().copyWith(
                        color: isSelected ? PhiColors.fg0 : PhiColors.fg1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
