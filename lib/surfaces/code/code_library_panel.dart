import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/dialog/confirm_dialog.dart';
import '../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../domain/project/entity_address.dart';
import '../../engine/state/code_library_controller.dart';
import '../../engine/state/code_tree_node.dart';

/// The Code surface's collapsible **script library panel** (issue #235, design
/// `docs/design/live-coding.md` §5) — a left sidebar mirroring the MIDI clip
/// library. It renders the `code.` namespace as a tree: groups as folders,
/// scripts ordered within them.
///
/// - **Selection** (tap a script) opens it in the editor — the editor swaps its
///   content to that script's source (any in-flight edit to the previous script
///   is flushed into the ordinary dirty tracking first).
/// - **Context menu** (the `⋯` button, or a right-click) offers new script · new
///   group · duplicate · rename · delete; delete routes through the delete-impact
///   dialog when the script is still referenced.
/// - **Drag** a row onto a group to re-parent it, onto the open panel body to
///   un-group it, or onto a sibling to reorder within a section.
///
/// All behaviour is driven through the [CodeLibraryController]; the panel itself
/// is a thin, [ChangeNotifier]-bound view. Collapsed by default (a thin strip),
/// so it stays out of the way until the performer opens it.
class CodeLibraryPanel extends StatefulWidget {
  const CodeLibraryPanel({
    required this.controller,
    this.initiallyExpanded = false,
    super.key,
  });

  final CodeLibraryController controller;

  /// Whether the panel starts expanded. Defaults to collapsed (a thin strip).
  final bool initiallyExpanded;

  /// Expanded panel width — matches the MIDI library panel's sibling.
  static const double expandedWidth = 232;

  /// Collapsed strip width — the same affordance as the right inspector.
  static const double collapsedWidth = 28;

  /// Key on the expand / collapse toggle.
  static const Key expandToggleKey = Key('CodeLibraryPanel.expandToggle');

  /// Key on the header's `+` add-menu button.
  static const Key addMenuKey = Key('CodeLibraryPanel.addMenu');

  /// Key on a node's row, by address — so tests can tap to select or find it.
  static Key rowKey(EntityAddress address) =>
      Key('CodeLibraryPanel.row.${address.format()}');

  /// Key on a row's context-menu (`⋯`) button, by address.
  static Key menuKey(EntityAddress address) =>
      Key('CodeLibraryPanel.menu.${address.format()}');

  /// Key on a row's drag handle, by address.
  static Key dragHandleKey(EntityAddress address) =>
      Key('CodeLibraryPanel.drag.${address.format()}');

  @override
  State<CodeLibraryPanel> createState() => _CodeLibraryPanelState();
}

class _CodeLibraryPanelState extends State<CodeLibraryPanel> {
  late bool _expanded = widget.initiallyExpanded;

  CodeLibraryController get _controller => widget.controller;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    // Snap the width (rather than animate it): animating would lay the
    // full-width tree out at intermediate narrow widths, overflowing its rows.
    return Container(
      width: _expanded
          ? CodeLibraryPanel.expandedWidth
          : CodeLibraryPanel.collapsedWidth,
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        border: Border.all(color: PhiColors.line1),
        borderRadius: PhiRadii.all2,
      ),
      clipBehavior: Clip.antiAlias,
      child: _expanded ? _buildExpanded(context) : _buildCollapsed(),
    );
  }

  Widget _buildCollapsed() {
    return Column(
      children: [
        _IconButton(
          buttonKey: CodeLibraryPanel.expandToggleKey,
          icon: Icons.chevron_right,
          tooltip: 'show scripts',
          onTap: _toggleExpanded,
        ),
        const SizedBox(height: PhiSpacing.s2),
        const RotatedBox(
          quarterTurns: 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: PhiSpacing.s1),
            child: _VerticalLabel(),
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final tree = _controller.tree;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              onAdd: () => _openAddMenu(group: null),
              onCollapse: _toggleExpanded,
            ),
            Expanded(
              child: DragTarget<EntityAddress>(
                // Dropping on the open body (outside any group) un-groups the
                // dragged node back to the top level.
                onWillAcceptWithDetails: (details) => !details.data.isTopLevel,
                onAcceptWithDetails: (details) =>
                    _controller.regroup(details.data, null),
                builder: (context, candidate, rejected) => Container(
                  color: candidate.isEmpty ? null : PhiColors.line0,
                  child: tree.isEmpty
                      ? const _EmptyHint()
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            vertical: PhiSpacing.s1,
                          ),
                          children: [
                            for (final node in tree) ..._buildRows(node, 0),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildRows(CodeTreeNode node, int depth) {
    if (node.isGroup) {
      return [
        _GroupRow(
          node: node,
          depth: depth,
          onMenu: (position) => _openRowMenu(node, position),
          onRegroupInto: (dragged) =>
              _controller.regroup(dragged, node.address),
        ),
        for (final child in node.children) ..._buildRows(child, depth + 1),
      ];
    }
    final address = node.address;
    return [
      _ScriptRow(
        node: node,
        depth: depth,
        selected: _controller.openAddress == address,
        onSelect: () => _controller.select(address),
        onMenu: (position) => _openRowMenu(node, position),
        onDropOnRow: (dragged) {
          if (dragged.parent == address.parent) {
            _controller.reorderBefore(dragged, address);
          } else {
            _controller.regroup(dragged, address.parent);
          }
        },
      ),
    ];
  }

  // ── menus ──────────────────────────────────────────────────────────────────

  Future<void> _openAddMenu({required EntityAddress? group}) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final choice = await showMenu<_AddAction>(
      context: context,
      position: RelativeRect.fromLTRB(80, 80, overlay.size.width - 80, 0),
      color: PhiColors.bg2,
      items: [
        for (final a in _AddAction.values)
          PopupMenuItem<_AddAction>(
            value: a,
            height: 34,
            child: Text(
              a.label,
              style: PhiType.monoS().copyWith(color: PhiColors.fg0),
            ),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AddAction.newScript:
        _controller.newScript(group: group);
      case _AddAction.newGroup:
        _controller.newGroup(group: group);
    }
  }

  Future<void> _openRowMenu(CodeTreeNode node, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    // A script's new-script / new-group create a sibling (under its parent); a
    // group's create inside it. Duplicate is script-only.
    final createGroup = node.isGroup ? node.address : node.address.parent;
    final actions = <_RowAction>[
      _RowAction.newScript,
      _RowAction.newGroup,
      if (!node.isGroup) _RowAction.duplicate,
      _RowAction.rename,
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
      case _RowAction.newScript:
        _controller.newScript(group: createGroup);
      case _RowAction.newGroup:
        _controller.newGroup(group: createGroup);
      case _RowAction.duplicate:
        _controller.duplicate(node.address);
      case _RowAction.rename:
        await _renameNode(node);
      case _RowAction.delete:
        await _deleteNode(node);
    }
  }

  Future<void> _renameNode(CodeTreeNode node) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: node.name),
    );
    if (name == null || name.trim().isEmpty) return;
    _controller.rename(node.address, name);
  }

  Future<void> _deleteNode(CodeTreeNode node) async {
    final impact = _controller.impactOf(node.address);
    final what = node.isGroup ? 'group' : 'script';
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
}

/// What the header / context `+` menu can add.
enum _AddAction {
  newScript('new script'),
  newGroup('new group');

  const _AddAction(this.label);

  final String label;
}

/// The per-row context-menu actions.
enum _RowAction {
  newScript('new script'),
  newGroup('new group'),
  duplicate('duplicate'),
  rename('rename…'),
  delete('delete');

  const _RowAction(this.label);

  final String label;
}

/// The expanded panel header: the SCRIPTS title, an add `+`, and the collapse
/// toggle.
class _Header extends StatelessWidget {
  const _Header({required this.onAdd, required this.onCollapse});

  final VoidCallback onAdd;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: PhiSpacing.s3),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'scripts'.toUpperCase(),
              style: PhiType.caption().copyWith(color: PhiColors.fg1),
            ),
          ),
          _IconButton(
            buttonKey: CodeLibraryPanel.addMenuKey,
            icon: Icons.add,
            tooltip: 'new…',
            onTap: onAdd,
          ),
          _IconButton(
            buttonKey: CodeLibraryPanel.expandToggleKey,
            icon: Icons.chevron_left,
            tooltip: 'hide scripts',
            onTap: onCollapse,
          ),
        ],
      ),
    );
  }
}

/// A group folder row — a drop target that re-parents a dragged node into it,
/// and a context menu.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.node,
    required this.depth,
    required this.onMenu,
    required this.onRegroupInto,
  });

  final CodeTreeNode node;
  final int depth;
  final void Function(Offset globalPosition) onMenu;
  final void Function(EntityAddress dragged) onRegroupInto;

  @override
  Widget build(BuildContext context) {
    return DragTarget<EntityAddress>(
      onWillAcceptWithDetails: (details) =>
          details.data != node.address &&
          !node.address.isDescendantOf(details.data),
      onAcceptWithDetails: (details) => onRegroupInto(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return _RowShell(
          address: node.address,
          depth: depth,
          highlighted: hovering,
          onMenu: onMenu,
          leading: const Icon(Icons.folder, size: 14, color: PhiColors.fg2),
          label: node.name,
          labelColor: PhiColors.fg1,
        );
      },
    );
  }
}

/// A script leaf row — tap to open in the editor, drag to reorder / regroup, and
/// a context menu.
class _ScriptRow extends StatelessWidget {
  const _ScriptRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.onSelect,
    required this.onMenu,
    required this.onDropOnRow,
  });

  final CodeTreeNode node;
  final int depth;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(Offset globalPosition) onMenu;
  final void Function(EntityAddress dragged) onDropOnRow;

  @override
  Widget build(BuildContext context) {
    final address = node.address;
    return DragTarget<EntityAddress>(
      onWillAcceptWithDetails: (details) => details.data != address,
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
          ),
        );
      },
    );
  }
}

/// The shared chrome of a row: selection / hover background, depth indent,
/// leading widget, label, and a `⋯` context-menu button (also fired by a
/// secondary tap anywhere on the row).
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.address,
    required this.depth,
    required this.onMenu,
    required this.leading,
    required this.label,
    required this.labelColor,
    this.selected = false,
    this.highlighted = false,
  });

  final EntityAddress address;
  final int depth;
  final void Function(Offset globalPosition) onMenu;
  final Widget leading;
  final String label;
  final Color labelColor;
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
        key: CodeLibraryPanel.rowKey(address),
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
            _IconButton(
              buttonKey: CodeLibraryPanel.menuKey(address),
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
          key: CodeLibraryPanel.dragHandleKey(address),
          size: 14,
          color: PhiColors.fg3,
        ),
      ),
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

/// The vertical SCRIPTS label shown on the collapsed strip.
class _VerticalLabel extends StatelessWidget {
  const _VerticalLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'scripts'.toUpperCase(),
      style: PhiType.caption().copyWith(color: PhiColors.fg2),
    );
  }
}

/// The empty-tree hint shown when the `code.` namespace has no scripts yet.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Text(
        'no scripts yet — use + to add one',
        style: PhiType.monoS().copyWith(color: PhiColors.fg3),
      ),
    );
  }
}

/// Modal that renames a script or group. Owns its [TextEditingController] so the
/// field's exit animation never outlives it.
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
