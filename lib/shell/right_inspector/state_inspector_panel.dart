import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/inline_editable_text/inline_editable_text.dart';
import '../../design/widgets/select/phi_select.dart';
import '../../design/widgets/select/phi_select_option.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/project_registry.dart';
import '../../domain/project/registry_group.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/project/registry_node.dart';
import '../../domain/session/session_state.dart';
import '../../domain/state_machine/slices/clip_slice_entry.dart';
import '../../domain/state_machine/slices/mix_slice_entry.dart';
import '../../domain/state_machine/slices/state_slice_category.dart';
import '../../domain/state_machine/slices/state_slices.dart';
import '../../domain/state_machine/slices/tempo_slice_entry.dart';
import '../../domain/state_machine/store/state_document.dart';
import '../../domain/state_machine/store/state_transition_spec.dart';
import '../../domain/state_machine/store/state_trigger.dart';
import '../../engine/state/state_entity_selection.dart';
import '../../engine/state/state_machine_controller.dart';
import '../../surfaces/state/state_trigger_editor.dart';
import 'no_selection_panel.dart';

/// A whole number without its `.0`, a fractional one as-is — `124`, `0.5`.
String _formatNumber(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : value.toString();

/// Inspector panel for a selected `state.` entity — the real SLICES /
/// ON ENTER / TRANSITIONS editors replacing the placeholders (design
/// `docs/design/state-graph.md` §6, issue #245).
///
/// - **Name** — inline edit renames through the controller's journaled
///   rename-refactor and re-publishes the selection at its new address.
/// - **SLICES** — the four categories with capture / clear / view; captured
///   entries listed with per-entry remove. An uncaptured category reads
///   *not captured* — meaningfully distinct from *captured · empty* ("no
///   clips playing" stops everything the state knows about).
/// - **ON ENTER** — a `PhiSelect` over the project's `code.` entities, or
///   none.
/// - **TRANSITIONS** — the outbound list (target, trigger kind + params,
///   label) with add / remove / edit here as well as on the canvas; the
///   trigger summary opens the shared [StateTriggerEditor].
///
/// Every edit threads through the [StateMachineController]'s journaled
/// commands, so the canvas — listening to the same controller — stays
/// consistent with edits made from either side.
class StateInspectorPanel extends StatelessWidget {
  const StateInspectorPanel({
    required this.selection,
    required this.session,
    super.key,
  });

  /// The selected `state.` entity plus the controller fronting it.
  final StateEntitySelection selection;

  /// The session the rename re-publishes the moved selection into.
  final SessionState session;

  /// The capture button of [category]'s slice block.
  static Key captureKey(StateSliceCategory category) =>
      Key('StateInspectorPanel.capture.${category.name}');

  /// The clear button of [category]'s slice block (present when captured).
  static Key clearKey(StateSliceCategory category) =>
      Key('StateInspectorPanel.clear.${category.name}');

  /// The per-entry remove of the captured clips entry for [clip].
  static Key removeClipEntryKey(EntityAddress clip) =>
      Key('StateInspectorPanel.removeClip.${clip.format()}');

  /// The per-entry remove of the captured mix entry for [bus].
  static Key removeMixEntryKey(EntityAddress bus) =>
      Key('StateInspectorPanel.removeMix.${bus.format()}');

  /// The per-entry remove of the captured variable [name].
  static Key removeVariableEntryKey(String name) =>
      Key('StateInspectorPanel.removeVariable.$name');

  /// The per-entry remove of the captured tempo entry for [domain].
  static Key removeTempoEntryKey(EntityAddress domain) =>
      Key('StateInspectorPanel.removeTempo.${domain.format()}');

  /// The ON ENTER `code.` picker.
  static const Key onEnterKey = Key('StateInspectorPanel.onEnter');

  /// The add-transition target picker.
  static const Key addTransitionKey = Key('StateInspectorPanel.addTransition');

  /// The trigger summary of the transition to [to] — tap opens the editor.
  static Key transitionTriggerKey(EntityAddress to) =>
      Key('StateInspectorPanel.trigger.${to.format()}');

  /// The inline-editable label of the transition to [to].
  static Key transitionLabelKey(EntityAddress to) =>
      Key('StateInspectorPanel.label.${to.format()}');

  /// The remove button of the transition to [to].
  static Key removeTransitionKey(EntityAddress to) =>
      Key('StateInspectorPanel.removeTransition.${to.format()}');

  @override
  Widget build(BuildContext context) {
    final controller = selection.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final node = controller.nodeAt(selection.address);
        final document = controller.documentOf(selection.address);
        // The selected entity is gone (deleted, or renamed from elsewhere) —
        // the selection is stale, so fall back to the empty panel.
        if (node == null || document == null) return const NoSelectionPanel();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STATE', style: PhiType.caption()),
            const SizedBox(height: PhiSpacing.s2),
            InlineEditableText(
              value: node.name,
              onChanged: (name) {
                final to = controller.rename(selection.address, name);
                if (to != null && to != selection.address) {
                  session.select(selection.withAddress(to));
                }
              },
              style: PhiType.monoL(),
            ),
            const SizedBox(height: PhiSpacing.s1),
            Text(
              node.address.format(),
              style: PhiType.small().copyWith(color: PhiColors.fg3),
            ),
            const SizedBox(height: PhiSpacing.s5),
            _SlicesSection(selection: selection, document: document),
            const SizedBox(height: PhiSpacing.s5),
            _OnEnterSection(selection: selection, document: document),
            const SizedBox(height: PhiSpacing.s5),
            _TransitionsSection(selection: selection, document: document),
          ],
        );
      },
    );
  }
}

/// SLICES — the four capture categories (design §4/§6): each a header row
/// with capture / clear and a body listing the captured entries with
/// per-entry remove.
class _SlicesSection extends StatelessWidget {
  const _SlicesSection({required this.selection, required this.document});

  final StateEntitySelection selection;
  final StateDocument document;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SLICES', style: PhiType.caption()),
        for (final category in StateSliceCategory.values) ...[
          const SizedBox(height: PhiSpacing.s3),
          _SliceCategoryBlock(
            selection: selection,
            slices: document.slices,
            category: category,
          ),
        ],
      ],
    );
  }
}

/// One slice category: `clips` / `mix` / `variables` / `tempos` with its
/// capture + clear actions and the captured-entry list.
class _SliceCategoryBlock extends StatelessWidget {
  const _SliceCategoryBlock({
    required this.selection,
    required this.slices,
    required this.category,
  });

  final StateEntitySelection selection;
  final StateSlices slices;
  final StateSliceCategory category;

  StateMachineController get _controller => selection.controller;

  @override
  Widget build(BuildContext context) {
    final captured = slices.isCaptured(category);
    final entries = captured
        ? _entries()
        : const <({String label, Key removeKey, VoidCallback remove})>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              category.name.toUpperCase(),
              style: PhiType.monoS().copyWith(
                color: PhiColors.fg2,
                fontSize: 9,
                letterSpacing: 0.08 * 9,
              ),
            ),
            const Spacer(),
            _TextAction(
              key: StateInspectorPanel.captureKey(category),
              label: 'capture',
              // Capture reads the live performance through the wired slice
              // source; a bare setup (no source) renders it disabled.
              onTap: _controller.sliceSource == null
                  ? null
                  : () => _controller.captureSlice(selection.address, category),
            ),
            if (captured) ...[
              const SizedBox(width: PhiSpacing.s2),
              _TextAction(
                key: StateInspectorPanel.clearKey(category),
                label: 'clear',
                onTap: () =>
                    _controller.clearSlice(selection.address, category),
              ),
            ],
          ],
        ),
        const SizedBox(height: PhiSpacing.s1),
        if (!captured)
          Text(
            'not captured',
            style: PhiType.mono().copyWith(color: PhiColors.fg3),
          )
        else ...[
          for (final entry in entries)
            _SliceEntryRow(
              entryKey: entry.removeKey,
              label: entry.label,
              onRemove: entry.remove,
            ),
          if (entries.isEmpty)
            Text(
              'captured · empty',
              style: PhiType.mono().copyWith(color: PhiColors.fg2),
            ),
        ],
      ],
    );
  }

  /// The captured entries of [category] — label, remove key, and the
  /// controller edit their `×` drives.
  List<({String label, Key removeKey, VoidCallback remove})> _entries() {
    final address = selection.address;
    final controller = _controller;
    switch (category) {
      case StateSliceCategory.clips:
        return [
          for (final e in slices.clips ?? const <ClipSliceEntry>[])
            (
              label: '${e.clip.name}${e.loop ? ' · loop' : ''}',
              removeKey: StateInspectorPanel.removeClipEntryKey(e.clip),
              remove: () => controller.removeClipSliceEntry(address, e.clip),
            ),
        ];
      case StateSliceCategory.mix:
        return [
          for (final e in slices.mix ?? const <MixSliceEntry>[])
            (
              label:
                  '${e.bus.name} · ${e.volume.toStringAsFixed(2)}'
                  '${e.muted ? ' · muted' : ''}',
              removeKey: StateInspectorPanel.removeMixEntryKey(e.bus),
              remove: () => controller.removeMixSliceEntry(address, e.bus),
            ),
        ];
      case StateSliceCategory.variables:
        return [
          for (final entry
              in (slices.variables ?? const <String, String>{}).entries)
            (
              label: '${entry.key} = ${entry.value}',
              removeKey: StateInspectorPanel.removeVariableEntryKey(entry.key),
              remove: () =>
                  controller.removeVariableSliceEntry(address, entry.key),
            ),
        ];
      case StateSliceCategory.tempos:
        return [
          for (final e in slices.tempos ?? const <TempoSliceEntry>[])
            (
              label: '${e.domain.name} · ${_formatNumber(e.bpm)} bpm',
              removeKey: StateInspectorPanel.removeTempoEntryKey(e.domain),
              remove: () => controller.removeTempoSliceEntry(address, e.domain),
            ),
        ];
    }
  }
}

/// One captured entry: its readable label plus the per-entry `×` remove.
class _SliceEntryRow extends StatelessWidget {
  const _SliceEntryRow({
    required this.entryKey,
    required this.label,
    required this.onRemove,
  });

  final Key entryKey;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: PhiSpacing.s0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: PhiType.mono(),
            ),
          ),
          _TextAction(key: entryKey, label: '×', onTap: onRemove),
        ],
      ),
    );
  }
}

/// ON ENTER — the optional `code.` entity evaluated on entry, picked from
/// the project's code tree (design §6).
class _OnEnterSection extends StatelessWidget {
  const _OnEnterSection({required this.selection, required this.document});

  final StateEntitySelection selection;
  final StateDocument document;

  @override
  Widget build(BuildContext context) {
    final controller = selection.controller;
    final options = <PhiSelectOption<EntityAddress?>>[
      const PhiSelectOption(value: null, label: 'none'),
      for (final code in _codeAddresses(controller.registry))
        PhiSelectOption(value: code, label: code.format()),
    ];
    // A stored script no longer in the project stays offered, so opening the
    // picker never silently rewrites it (the trigger editor's precedent).
    final stored = document.onEnter;
    if (stored != null && options.every((o) => o.value != stored)) {
      options.insert(
        1,
        PhiSelectOption(value: stored, label: '${stored.format()} · missing'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ON ENTER', style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s2),
        PhiSelect<EntityAddress?>.flat(
          key: StateInspectorPanel.onEnterKey,
          value: document.onEnter,
          options: options,
          onChanged: (code) => controller.setOnEnter(selection.address, code),
        ),
      ],
    );
  }

  /// Every `code.` entity in [registry], in registry order (groups
  /// flattened, pre-order) — the code tree the picker offers.
  static List<EntityAddress> _codeAddresses(ProjectRegistry registry) {
    final result = <EntityAddress>[];
    void walk(List<RegistryNode> nodes, List<String> prefix) {
      for (final node in nodes) {
        if (node is RegistryGroup) {
          walk(node.children.toList(), [...prefix, node.name]);
        } else {
          result.add(
            EntityAddress(
              kind: RegistryKinds.code,
              segments: [...prefix, node.name],
            ),
          );
        }
      }
    }

    walk(registry.childrenOfKind(RegistryKinds.code), const []);
    return result;
  }
}

/// TRANSITIONS — the ordered outbound list with per-row trigger editing,
/// label editing and remove, plus the add-transition target picker
/// (design §6: add / remove / edit here as well as on the canvas).
class _TransitionsSection extends StatelessWidget {
  const _TransitionsSection({required this.selection, required this.document});

  final StateEntitySelection selection;
  final StateDocument document;

  @override
  Widget build(BuildContext context) {
    final controller = selection.controller;
    final targeted = {for (final spec in document.transitions) spec.to};
    final candidates = [
      for (final node in controller.states)
        if (node.address != selection.address &&
            !targeted.contains(node.address))
          PhiSelectOption<EntityAddress>(
            value: node.address,
            label: node.address.name,
          ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TRANSITIONS', style: PhiType.caption()),
        const SizedBox(height: PhiSpacing.s1),
        if (document.transitions.isEmpty)
          Text('—', style: PhiType.mono().copyWith(color: PhiColors.fg3))
        else
          for (final spec in document.transitions)
            _TransitionRow(selection: selection, spec: spec),
        const SizedBox(height: PhiSpacing.s2),
        PhiSelect<EntityAddress>.flat(
          key: StateInspectorPanel.addTransitionKey,
          value: null,
          placeholder: 'add transition…',
          options: candidates,
          onChanged: (target) => controller.connect(selection.address, target),
        ),
      ],
    );
  }
}

/// One outbound transition: target + remove on the first line, then the
/// tappable trigger summary (kind + params — opens the shared editor) and
/// the inline-editable label.
class _TransitionRow extends StatelessWidget {
  const _TransitionRow({required this.selection, required this.spec});

  final StateEntitySelection selection;
  final StateTransitionSpec spec;

  StateMachineController get _controller => selection.controller;

  @override
  Widget build(BuildContext context) {
    final labelled = spec.label != null;
    return Padding(
      padding: const EdgeInsets.only(top: PhiSpacing.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '→ ${spec.to.name}',
                  overflow: TextOverflow.ellipsis,
                  style: PhiType.mono(),
                ),
              ),
              _TextAction(
                key: StateInspectorPanel.removeTransitionKey(spec.to),
                label: '×',
                onTap: () => _controller.disconnect(selection.address, spec.to),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: PhiSpacing.s3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _TextAction(
                key: StateInspectorPanel.transitionTriggerKey(spec.to),
                label: _triggerSummary(spec.trigger),
                onTap: () => _editTrigger(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: PhiSpacing.s3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InlineEditableText(
                key: StateInspectorPanel.transitionLabelKey(spec.to),
                value: spec.label ?? 'label…',
                onChanged: (label) => _controller.setTransitionLabel(
                  selection.address,
                  spec.to,
                  // Committing the untouched placeholder must not store it.
                  label == 'label…' ? null : label,
                ),
                style: PhiType.small().copyWith(
                  color: labelled ? PhiColors.fg1 : PhiColors.fg3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The readable kind + params line (design §6): `manual`, `code`,
  /// `timed · 16 beats on drum`, `variable · section = a`.
  String _triggerSummary(StateTrigger trigger) => switch (trigger) {
    ManualTrigger() => 'manual',
    CodeTrigger() => 'code',
    TimedTrigger(:final beats, :final domain) =>
      'timed · ${_formatNumber(beats)} beats on ${domain.name}',
    VariableTrigger(:final name, :final value) => 'variable · $name = $value',
  };

  /// Open the shared trigger editor and write the edited trigger back as one
  /// journaled payload update — the canvas path, driven from the inspector.
  Future<void> _editTrigger(BuildContext context) async {
    final controller = _controller;
    final trigger = controller.triggerOf(selection.address, spec.to);
    if (trigger == null) return;
    final edited = await StateTriggerEditor.show(
      context,
      initial: trigger,
      domains: StateTriggerEditor.domainOptionsOf(controller.registry),
      variables: selection.variables?.variables.toList() ?? const [],
    );
    if (edited == null || edited == trigger) return;
    controller.setTrigger(selection.address, spec.to, edited);
  }
}

/// A small tappable text action (`capture`, `clear`, `×`, the trigger
/// summary). A `null` [onTap] renders it dimmed and inert.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s1,
            vertical: PhiSpacing.s0,
          ),
          child: Text(
            label,
            style: PhiType.monoS().copyWith(
              fontSize: 10,
              color: onTap == null ? PhiColors.fg3 : PhiColors.fg2,
            ),
          ),
        ),
      ),
    );
  }
}
