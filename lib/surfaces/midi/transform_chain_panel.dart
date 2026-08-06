import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/tokens/phi_voices.dart';
import '../../domain/midi/builtin_transform_catalog.dart';
import '../../domain/midi/custom_transform_registry.dart';
import '../../domain/midi/midi_transform.dart';
import '../../domain/midi/midi_transform_chain.dart';
import '../../domain/midi/midi_transform_kind.dart';
import 'param_editors/typed_param_editors.dart';
import 'transform_chip.dart';
import 'transform_param_editor.dart';

/// 250px right-hand sidebar listing the [MidiTransformChain]'s transforms.
///
/// The header `+` opens a grouped menu of every addable transform — the
/// built-in catalogue plus any performer-authored [registry] transforms
/// (issue #38), sectioned by family (pitch · time · voice · struct). Picking
/// one appends it to the chain with sensible defaults.
///
/// Chips can be reordered by dragging their handle, toggled active by tapping,
/// and right-clicked for a context menu (remove · duplicate · rename · edit
/// parameters).
class TransformChainPanel extends StatefulWidget {
  const TransformChainPanel({required this.chain, this.registry, super.key});

  final MidiTransformChain chain;
  final CustomTransformRegistry? registry;

  @override
  State<TransformChainPanel> createState() => _TransformChainPanelState();
}

class _TransformChainPanelState extends State<TransformChainPanel> {
  bool _menuOpen = false;

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _add(MidiTransform Function() build) {
    widget.chain.add(build());
    setState(() => _menuOpen = false);
  }

  // ── Per-chip context actions ─────────────────────────────────────────────

  Future<void> _showChipMenu(Offset globalPosition, int index) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    // "edit parameters…" greys out only for chips with nothing to edit (e.g. a
    // parameterless stub). A transform is editable if it exposes scalar params
    // or has a dedicated typed editor (issue #95).
    final transform = index < widget.chain.transforms.length
        ? widget.chain.transforms[index]
        : null;
    final editable =
        transform != null &&
        (transform.params.isNotEmpty || hasTypedEditor(transform));
    final action = await showMenu<_ChipAction>(
      context: context,
      position: position,
      color: PhiColors.bg2,
      items: [
        for (final a in _ChipAction.values)
          PopupMenuItem<_ChipAction>(
            value: a,
            height: 32,
            enabled: a != _ChipAction.editParams || editable,
            child: Text(
              a.label,
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: a != _ChipAction.editParams || editable
                    ? PhiColors.fg0
                    : PhiColors.fg3,
              ),
            ),
          ),
      ],
    );
    if (action == null || !mounted) return;
    // The list can only change via this same modal path, so the index is still
    // valid; guard anyway against a mutation racing in from playback.
    final transforms = widget.chain.transforms;
    if (index >= transforms.length) return;
    switch (action) {
      case _ChipAction.remove:
        widget.chain.removeAt(index);
      case _ChipAction.duplicate:
        widget.chain.insert(index + 1, transforms[index].copyWith());
      case _ChipAction.rename:
        await _renameChip(index);
      case _ChipAction.editParams:
        await _editChipParams(index);
    }
  }

  Future<void> _editChipParams(int index) async {
    if (index >= widget.chain.transforms.length) return;
    // Table/rule-list transforms get their dedicated typed dialog; the rest
    // fall back to the generic scalar editor.
    final typed = buildTypedParamEditor(widget.chain, index);
    await showDialog<void>(
      context: context,
      builder: (context) =>
          typed ?? TransformParamEditor(chain: widget.chain, index: index),
    );
  }

  Future<void> _renameChip(int index) async {
    final transforms = widget.chain.transforms;
    if (index >= transforms.length) return;
    final label = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: transforms[index].label),
    );
    if (label == null || label.trim().isEmpty || !mounted) return;
    final current = widget.chain.transforms;
    if (index >= current.length) return;
    widget.chain.replaceAt(index, current[index].copyWith(label: label.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final transforms = widget.chain.transforms;
    return Container(
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(menuOpen: _menuOpen, onAddTap: _toggleMenu),
          if (_menuOpen) _AddMenu(registry: widget.registry, onPick: _add),
          Expanded(
            child: ReorderableListView(
              padding: const EdgeInsets.all(6),
              buildDefaultDragHandles: false,
              // `onReorderItem` reports the item's **final** index — already
              // adjusted for the removal at the old index — and
              // `chain.reorder` speaks that same contract (issue #427).
              onReorderItem: widget.chain.reorder,
              children: [
                for (var i = 0; i < transforms.length; i++)
                  _ChipRow(
                    key: ValueKey(i),
                    index: i,
                    transform: transforms[i],
                    onToggle: () =>
                        widget.chain.setActiveAt(i, !transforms[i].active),
                    onContext: (pos) => _showChipMenu(pos, i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One reorderable chip row: a drag handle plus the [TransformChip].
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.index,
    required this.transform,
    required this.onToggle,
    required this.onContext,
    super.key,
  });

  final int index;
  final MidiTransform transform;
  final VoidCallback onToggle;
  final void Function(Offset globalPosition) onContext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: PhiColors.fg3,
                ),
              ),
            ),
          ),
          Expanded(
            child: TransformChip(
              transform: transform,
              onToggle: onToggle,
              onContext: onContext,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.menuOpen, required this.onAddTap});

  final bool menuOpen;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Text(
            'transform chain'.toUpperCase(),
            style: PhiType.caption().copyWith(color: PhiColors.fg1),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAddTap,
            child: Text(
              menuOpen ? '×' : '+',
              style: PhiType.monoS().copyWith(color: PhiColors.fg1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grouped dropdown of every addable transform, shown under the header when the
/// `+` is open: the built-in [BuiltinTransformCatalog] plus the [registry]'s
/// custom transforms (issue #38), sectioned by family. Rebuilds with its host
/// (the viewport merges the registry into its listenable) so a hot-registered
/// transform appears live.
class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.registry, required this.onPick});

  final CustomTransformRegistry? registry;
  final void Function(MidiTransform Function() build) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PhiColors.bg2,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final kind in MidiTransformKind.values) ..._section(kind),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(MidiTransformKind kind) {
    final color = PhiVoices.color(kind.voiceIndex);
    final customs =
        registry?.definitions
            .where((d) => d.kind == kind)
            .toList(growable: false) ??
        const [];
    return [
      _SectionHeader(tag: kind.tag, color: color),
      for (final entry in BuiltinTransformCatalog.forKind(kind))
        _MenuRow(
          label: entry.name,
          color: color,
          onTap: () => onPick(entry.build),
        ),
      for (final def in customs)
        _MenuRow(
          label: def.name,
          color: color,
          trailing: 'custom',
          onTap: () => onPick(def.instantiate),
        ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.tag, required this.color});

  final String tag;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Text(
        tag.toUpperCase(),
        style: PhiType.monoS().copyWith(
          fontSize: 8,
          color: color,
          letterSpacing: 0.08 * 8,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final Color color;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 5, 10, 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: PhiType.monoS().copyWith(
                  fontSize: 11,
                  color: PhiColors.fg0,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: PhiType.monoS().copyWith(
                  fontSize: 8,
                  color: PhiColors.fg3,
                  letterSpacing: 0.08 * 8,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Modal that renames a chip. Owns its [TextEditingController] so the field's
/// exit animation never outlives it — disposing it from the caller races the
/// pop transition and throws "used after disposed".
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PhiColors.bg1,
      title: Text(
        'rename transform',
        style: PhiType.caption().copyWith(color: PhiColors.fg1),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: PhiType.monoS().copyWith(color: PhiColors.fg0),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('rename')),
      ],
    );
  }
}

/// The per-chip context-menu actions.
enum _ChipAction {
  remove('remove'),
  duplicate('duplicate'),
  rename('rename…'),
  editParams('edit parameters…');

  const _ChipAction(this.label);

  final String label;
}
