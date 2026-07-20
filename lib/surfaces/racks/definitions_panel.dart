import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/dialog/confirm_dialog.dart';
import '../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../domain/fx/fx_kind.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/project/registry_kinds.dart';
import '../../domain/synth/synth_kind.dart';
import '../../engine/state/rack_definitions_controller.dart';
import '../../engine/state/rack_tree_node.dart';

/// The racks surface's **definitions pane** (issue #209, design
/// `docs/design/racks-and-voices.md` §8) — the left column of the three-pane
/// racks layout. It renders the `synth.` and `fx.` registry namespaces as two
/// independent trees (SYNTHS above, EFFECTS below): groups as folders,
/// definitions ordered within them.
///
/// - **Selection** (tap a definition) drives the center editor pane.
/// - **Add** (`+` on a section header, or on a group row) opens a per-kind menu
///   — sine · va · fm · sampler for synths, one entry per real [FxKind] for
///   effects — plus *new group*.
/// - **Context menu** (the `⋯` button, or a right-click) offers duplicate (leaf
///   only), rename, delete, and *new group*; delete routes through the
///   delete-impact dialog when the definition is still referenced.
/// - **Drag** a definition onto a group to re-parent it, onto the section body to
///   un-group it, or onto a sibling to reorder within a section.
///
/// All behaviour is driven through the [RackDefinitionsController]; the panel is
/// a thin, [ChangeNotifier]-bound view. The center per-kind editors land in #212;
/// here selection routes to a placeholder.
class DefinitionsPanel extends StatefulWidget {
  const DefinitionsPanel({required this.controller, super.key});

  final RackDefinitionsController controller;

  /// Fixed pane width — the left column of the three-pane racks layout.
  static const double width = 264;

  /// Key on the SYNTHS section add `+` button.
  static const Key synthAddKey = Key('DefinitionsPanel.synthAdd');

  /// Key on the EFFECTS section add `+` button.
  static const Key fxAddKey = Key('DefinitionsPanel.fxAdd');

  /// Key on an add-menu item, by namespace kind (`synth`/`fx`) and tag (the
  /// definition kind name, or `group`).
  static Key addItemKey(String kind, String tag) =>
      Key('DefinitionsPanel.addItem.$kind.$tag');

  /// Key on a node's row, by address — so tests can tap to select or find it.
  static Key rowKey(EntityAddress address) =>
      Key('DefinitionsPanel.row.${address.format()}');

  /// Key on a group row's own add `+` button, by address.
  static Key groupAddKey(EntityAddress address) =>
      Key('DefinitionsPanel.groupAdd.${address.format()}');

  /// Key on a row's context-menu (`⋯`) button, by address.
  static Key menuKey(EntityAddress address) =>
      Key('DefinitionsPanel.menu.${address.format()}');

  /// Key on a row's drag handle, by address.
  static Key dragHandleKey(EntityAddress address) =>
      Key('DefinitionsPanel.drag.${address.format()}');

  @override
  State<DefinitionsPanel> createState() => _DefinitionsPanelState();
}

class _DefinitionsPanelState extends State<DefinitionsPanel> {
  RackDefinitionsController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: DefinitionsPanel.width,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(right: BorderSide(color: PhiColors.line1)),
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Section(
                  title: 'synths',
                  addKey: DefinitionsPanel.synthAddKey,
                  kind: RegistryKinds.synth,
                  nodes: _controller.synthTree,
                  selected: _controller.selected,
                  emptyHint: 'no synths — use + to add one',
                  onAdd: (group) => _openAddMenu(RegistryKinds.synth, group),
                  onSelect: _controller.select,
                  onMenu: _openRowMenu,
                  onDropOnRow: _dropOnRow,
                  onRegroupInto: (dragged, group) =>
                      _controller.regroup(dragged, group),
                  onDropOnBody: (dragged) => _controller.regroup(dragged, null),
                ),
              ),
              const Divider(height: 1, color: PhiColors.line1),
              Expanded(
                child: _Section(
                  title: 'effects',
                  addKey: DefinitionsPanel.fxAddKey,
                  kind: RegistryKinds.fx,
                  nodes: _controller.fxTree,
                  selected: _controller.selected,
                  emptyHint: 'no effects — use + to add one',
                  onAdd: (group) => _openAddMenu(RegistryKinds.fx, group),
                  onSelect: _controller.select,
                  onMenu: _openRowMenu,
                  onDropOnRow: _dropOnRow,
                  onRegroupInto: (dragged, group) =>
                      _controller.regroup(dragged, group),
                  onDropOnBody: (dragged) => _controller.regroup(dragged, null),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _dropOnRow(EntityAddress dragged, EntityAddress onto) {
    if (dragged.parent == onto.parent) {
      _controller.reorderBefore(dragged, onto);
    } else {
      _controller.regroup(dragged, onto.parent);
    }
  }

  // ── menus ──────────────────────────────────────────────────────────────────

  Future<void> _openAddMenu(String kind, EntityAddress? group) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final items = <PopupMenuEntry<String>>[
      for (final tag in _addTagsFor(kind))
        PopupMenuItem<String>(
          key: DefinitionsPanel.addItemKey(kind, tag),
          value: tag,
          height: 34,
          child: Text(
            tag,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        key: DefinitionsPanel.addItemKey(kind, 'group'),
        value: 'group',
        height: 34,
        child: Text(
          'new group',
          style: PhiType.monoS().copyWith(color: PhiColors.fg1),
        ),
      ),
    ];
    final tag = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(60, 120, overlay.size.width - 60, 0),
      color: PhiColors.bg2,
      items: items,
    );
    if (tag == null || !mounted) return;
    if (tag == 'group') {
      _controller.newGroup(kind, group: group);
      return;
    }
    if (kind == RegistryKinds.synth) {
      _controller.newSynth(_synthKindByName(tag), group: group);
    } else {
      _controller.newFx(_fxKindByName(tag), group: group);
    }
  }

  /// The definition-kind tags addable in the [kind] namespace — the four synth
  /// kinds, or every real [FxKind] (the reserved `patcherInsert` has no
  /// materialisation yet, so it is not offered).
  List<String> _addTagsFor(String kind) {
    if (kind == RegistryKinds.synth) {
      return [for (final k in SynthKind.values) k.name];
    }
    return [
      for (final k in FxKind.values)
        if (k != FxKind.patcherInsert) k.name,
    ];
  }

  Future<void> _openRowMenu(RackTreeNode node, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    final actions = <_RowAction>[
      if (!node.isGroup) _RowAction.duplicate,
      _RowAction.rename,
      _RowAction.newGroup,
      _RowAction.delete,
    ];
    final action = await showMenu<_RowAction>(
      context: context,
      position: position,
      color: PhiColors.bg2,
      items: [
        for (final a in actions)
          PopupMenuItem<_RowAction>(
            value: a,
            height: 34,
            child: Text(
              a.label,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            ),
          ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _RowAction.duplicate:
        _controller.duplicate(node.address);
      case _RowAction.rename:
        await _renameNode(node);
      case _RowAction.newGroup:
        // A group's create nests inside it; a leaf's creates a sibling.
        _controller.newGroup(
          node.address.kind,
          group: node.isGroup ? node.address : node.address.parent,
        );
      case _RowAction.delete:
        await _deleteNode(node);
    }
  }

  Future<void> _renameNode(RackTreeNode node) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: node.name),
    );
    if (name == null || name.trim().isEmpty) return;
    _controller.rename(node.address, name);
  }

  Future<void> _deleteNode(RackTreeNode node) async {
    final impact = _controller.impactOf(node.address);
    final what = node.isGroup ? 'group' : node.address.kind;
    final bool confirmed;
    if (impact.hasReferrers) {
      confirmed = await DeleteImpactDialog.show(
        context,
        title: 'delete $what',
        message:
            '${node.name} is still referenced — deleting it strands these:',
        referrers: [for (final r in impact.referrers) r.format()],
      );
    } else {
      confirmed = await ConfirmDialog.show(
        context,
        title: 'delete $what',
        message: 'Delete "${node.name}"?',
        confirmLabel: 'delete',
      );
    }
    if (!confirmed) return;
    _controller.delete(node.address);
  }

  static SynthKind _synthKindByName(String name) =>
      SynthKind.values.firstWhere((k) => k.name == name);

  static FxKind _fxKindByName(String name) =>
      FxKind.values.firstWhere((k) => k.name == name);
}

/// The per-row context-menu actions.
enum _RowAction {
  duplicate('duplicate'),
  rename('rename…'),
  newGroup('new group'),
  delete('delete');

  const _RowAction(this.label);

  final String label;
}

/// One labelled definition section (SYNTHS or EFFECTS): a header with an add
/// `+`, then the tree, all wrapped in a body drop-target that un-groups a dropped
/// same-kind definition back to the top level.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.addKey,
    required this.kind,
    required this.nodes,
    required this.selected,
    required this.emptyHint,
    required this.onAdd,
    required this.onSelect,
    required this.onMenu,
    required this.onDropOnRow,
    required this.onRegroupInto,
    required this.onDropOnBody,
  });

  final String title;
  final Key addKey;
  final String kind;
  final List<RackTreeNode> nodes;
  final EntityAddress? selected;
  final String emptyHint;
  final void Function(EntityAddress? group) onAdd;
  final ValueChanged<EntityAddress> onSelect;
  final void Function(RackTreeNode node, Offset globalPosition) onMenu;
  final void Function(EntityAddress dragged, EntityAddress onto) onDropOnRow;
  final void Function(EntityAddress dragged, EntityAddress group) onRegroupInto;
  final ValueChanged<EntityAddress> onDropOnBody;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(left: PhiSpacing.s3),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PhiColors.line1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: PhiType.caption().copyWith(color: PhiColors.fg1),
                ),
              ),
              _IconButton(
                buttonKey: addKey,
                icon: Icons.add,
                tooltip: 'add…',
                onTap: () => onAdd(null),
              ),
            ],
          ),
        ),
        Expanded(
          child: DragTarget<EntityAddress>(
            onWillAcceptWithDetails: (details) =>
                details.data.kind == kind && !details.data.isTopLevel,
            onAcceptWithDetails: (details) => onDropOnBody(details.data),
            builder: (context, candidate, rejected) => Container(
              color: candidate.isEmpty ? null : PhiColors.line0,
              child: nodes.isEmpty
                  ? _EmptyHint(text: emptyHint)
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                        vertical: PhiSpacing.s1,
                      ),
                      children: [
                        for (final node in nodes) ..._buildRows(node, 0),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRows(RackTreeNode node, int depth) {
    if (node.isGroup) {
      return [
        _GroupRow(
          node: node,
          depth: depth,
          onAdd: () => onAdd(node.address),
          onMenu: (position) => onMenu(node, position),
          onRegroupInto: (dragged) => onRegroupInto(dragged, node.address),
        ),
        for (final child in node.children) ..._buildRows(child, depth + 1),
      ];
    }
    return [
      _DefinitionRow(
        node: node,
        depth: depth,
        selected: selected == node.address,
        onSelect: () => onSelect(node.address),
        onMenu: (position) => onMenu(node, position),
        onDropOnRow: (dragged) => onDropOnRow(dragged, node.address),
      ),
    ];
  }
}

/// A group folder row — a drop target that re-parents a dragged same-kind
/// definition into it, an add `+`, and a context menu.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.node,
    required this.depth,
    required this.onAdd,
    required this.onMenu,
    required this.onRegroupInto,
  });

  final RackTreeNode node;
  final int depth;
  final VoidCallback onAdd;
  final void Function(Offset globalPosition) onMenu;
  final void Function(EntityAddress dragged) onRegroupInto;

  @override
  Widget build(BuildContext context) {
    return DragTarget<EntityAddress>(
      onWillAcceptWithDetails: (details) =>
          details.data.kind == node.address.kind &&
          details.data != node.address &&
          !node.address.isDescendantOf(details.data),
      onAcceptWithDetails: (details) => onRegroupInto(details.data),
      builder: (context, candidate, rejected) {
        return _RowShell(
          address: node.address,
          depth: depth,
          highlighted: candidate.isNotEmpty,
          onMenu: onMenu,
          leading: const Icon(Icons.folder, size: 14, color: PhiColors.fg2),
          label: node.name,
          labelColor: PhiColors.fg1,
          trailing: [
            _IconButton(
              buttonKey: DefinitionsPanel.groupAddKey(node.address),
              icon: Icons.add,
              tooltip: 'add here…',
              onTap: onAdd,
            ),
          ],
        );
      },
    );
  }
}

/// A definition leaf row — tap to select (drives the editor pane), drag to
/// reorder / regroup, a kind chip, and a context menu.
class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.onSelect,
    required this.onMenu,
    required this.onDropOnRow,
  });

  final RackTreeNode node;
  final int depth;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(Offset globalPosition) onMenu;
  final void Function(EntityAddress dragged) onDropOnRow;

  @override
  Widget build(BuildContext context) {
    final address = node.address;
    return DragTarget<EntityAddress>(
      onWillAcceptWithDetails: (details) =>
          details.data.kind == address.kind && details.data != address,
      onAcceptWithDetails: (details) => onDropOnRow(details.data),
      builder: (context, candidate, rejected) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          child: _RowShell(
            address: address,
            depth: depth,
            selected: selected,
            highlighted: candidate.isNotEmpty,
            onMenu: onMenu,
            leading: _DragHandle(address: address, name: node.name),
            label: node.name,
            labelColor: selected ? PhiColors.fg0 : PhiColors.fg1,
            trailing: [if (node.kindTag != null) _KindChip(tag: node.kindTag!)],
          ),
        );
      },
    );
  }
}

/// The shared chrome of a row: selection / hover background, depth indent,
/// leading widget, label, trailing controls, and a `⋯` context-menu button (also
/// fired by a secondary tap anywhere on the row).
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.address,
    required this.depth,
    required this.onMenu,
    required this.leading,
    required this.label,
    required this.labelColor,
    required this.trailing,
    this.selected = false,
    this.highlighted = false,
  });

  final EntityAddress address;
  final int depth;
  final void Function(Offset globalPosition) onMenu;
  final Widget leading;
  final String label;
  final Color labelColor;
  final List<Widget> trailing;
  final bool selected;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? PhiColors.bg3
        : highlighted
        ? PhiColors.line1
        : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) => onMenu(d.globalPosition),
      child: Container(
        key: DefinitionsPanel.rowKey(address),
        height: 26,
        padding: EdgeInsets.only(
          left: PhiSpacing.s2 + depth * PhiSpacing.s3,
          right: PhiSpacing.s0,
        ),
        decoration: BoxDecoration(
          color: background,
          border: selected
              ? const Border(
                  left: BorderSide(color: PhiColors.voice1, width: 2),
                )
              : null,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: PhiSpacing.s1),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: PhiType.monoS().copyWith(color: labelColor),
              ),
            ),
            ...trailing,
            _IconButton(
              buttonKey: DefinitionsPanel.menuKey(address),
              icon: Icons.more_horiz,
              tooltip: 'more…',
              onTap: () {
                final box = context.findRenderObject() as RenderBox?;
                final at = box == null
                    ? Offset.zero
                    : box.localToGlobal(box.size.center(Offset.zero));
                onMenu(at);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The grip that starts a row drag. Feedback is a compact floating name chip.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.address, required this.name});

  final EntityAddress address;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Draggable<EntityAddress>(
      data: address,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PhiSpacing.s2,
            vertical: PhiSpacing.s1,
          ),
          decoration: BoxDecoration(
            color: PhiColors.bg3,
            border: Border.all(color: PhiColors.line2),
            borderRadius: PhiRadii.all1,
          ),
          child: Text(
            name,
            style: PhiType.monoS().copyWith(color: PhiColors.fg0),
          ),
        ),
      ),
      childWhenDragging: const Icon(
        Icons.drag_indicator,
        size: 14,
        color: PhiColors.line2,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Icon(
          Icons.drag_indicator,
          key: DefinitionsPanel.dragHandleKey(address),
          size: 14,
          color: PhiColors.fg3,
        ),
      ),
    );
  }
}

/// A compact kind tag chip shown on a definition leaf (`va`, `lowpass`, …).
class _KindChip extends StatelessWidget {
  const _KindChip({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: PhiSpacing.s1),
      padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s1),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        borderRadius: PhiRadii.all1,
        border: Border.all(color: PhiColors.line1),
      ),
      child: Text(tag, style: PhiType.caption().copyWith(color: PhiColors.fg2)),
    );
  }
}

/// A compact square icon button styled to the panel's chrome.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.buttonKey,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon, size: 15, color: PhiColors.fg2),
          ),
        ),
      ),
    );
  }
}

/// The empty-section hint shown when a definition namespace has no entries yet.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Text(text, style: PhiType.monoS().copyWith(color: PhiColors.fg3)),
    );
  }
}

/// Modal that renames a definition or group. Owns its [TextEditingController] so
/// the field's exit animation never outlives it (mirrors the library panel).
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
        'rename',
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
