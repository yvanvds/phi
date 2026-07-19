import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_spacing.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/dialog/confirm_dialog.dart';
import '../../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../../domain/project/entity_address.dart';
import '../../../engine/state/clip_library_controller.dart';
import '../../../engine/state/clip_tree_node.dart';

/// The MIDI surface's collapsible **library panel** (issue #188, design
/// `docs/design/midi-clips.md` §3, §4) — a left sidebar mirroring the transform
/// chain panel on the right. It renders the `clip.` namespace as a tree: groups
/// as folders, clips ordered within them.
///
/// - **Selection** (tap a clip) opens it in the editor — its session becomes the
///   edited one, so the roll, ghost and graph all swap to it.
/// - **Context menu** (the `⋯` button, or a right-click) offers new clip · new
///   group · duplicate · rename · delete; delete routes through the delete-impact
///   dialog when the clip is still referenced.
/// - **Drag** a row onto a group to re-parent it, onto the open panel body to
///   un-group it, or onto a sibling to reorder within a section.
/// - **Per-row play / loop toggles** and a playing indicator; a group row plays /
///   stops its whole subtree; the header carries **stop-all**.
///
/// All behaviour is driven through the [ClipLibraryController]; the panel itself
/// is a thin, [ChangeNotifier]-bound view. Collapsed by default (a thin strip),
/// so it stays out of the way until the performer opens it.
class LibraryPanel extends StatefulWidget {
  const LibraryPanel({
    required this.controller,
    this.initiallyExpanded = false,
    super.key,
  });

  final ClipLibraryController controller;

  /// Whether the panel starts expanded. Defaults to collapsed (a thin strip).
  final bool initiallyExpanded;

  /// Expanded panel width — matches the transform chain panel's 250px sibling
  /// closely enough to read as its mirror.
  static const double expandedWidth = 232;

  /// Collapsed strip width — the same affordance as the right inspector.
  static const double collapsedWidth = 28;

  /// Key on the expand / collapse toggle.
  static const Key expandToggleKey = Key('LibraryPanel.expandToggle');

  /// Key on the header's `+` add-menu button.
  static const Key addMenuKey = Key('LibraryPanel.addMenu');

  /// Key on the header's stop-all button.
  static const Key stopAllKey = Key('LibraryPanel.stopAll');

  /// Key on a node's row, by address — so tests can tap to select or find it.
  static Key rowKey(EntityAddress address) =>
      Key('LibraryPanel.row.${address.format()}');

  /// Key on a clip row's play / stop toggle, by address.
  static Key playKey(EntityAddress address) =>
      Key('LibraryPanel.play.${address.format()}');

  /// Key on a clip row's loop toggle, by address.
  static Key loopKey(EntityAddress address) =>
      Key('LibraryPanel.loop.${address.format()}');

  /// Key on a clip row's playing indicator dot, present only while it plays.
  static Key playingDotKey(EntityAddress address) =>
      Key('LibraryPanel.playing.${address.format()}');

  /// Key on a group row's play / stop (subtree) toggle, by address.
  static Key groupPlayKey(EntityAddress address) =>
      Key('LibraryPanel.groupPlay.${address.format()}');

  /// Key on a row's context-menu (`⋯`) button, by address.
  static Key menuKey(EntityAddress address) =>
      Key('LibraryPanel.menu.${address.format()}');

  /// Key on a row's drag handle, by address.
  static Key dragHandleKey(EntityAddress address) =>
      Key('LibraryPanel.drag.${address.format()}');

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  late bool _expanded = widget.initiallyExpanded;

  ClipLibraryController get _controller => widget.controller;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    // Snap the width (rather than animate it): animating would lay the
    // full-width tree out at intermediate narrow widths, overflowing its rows.
    return Container(
      width: _expanded
          ? LibraryPanel.expandedWidth
          : LibraryPanel.collapsedWidth,
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
          buttonKey: LibraryPanel.expandToggleKey,
          icon: Icons.chevron_right,
          tooltip: 'show library',
          onTap: _toggleExpanded,
        ),
        const SizedBox(height: PhiSpacing.s2),
        // A vertical LIBRARY label, so the collapsed strip still reads as one.
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
              onStopAll: _controller.stopAll,
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

  List<Widget> _buildRows(ClipTreeNode node, int depth) {
    if (node.isGroup) {
      return [
        _GroupRow(
          node: node,
          depth: depth,
          playing: _controller.isGroupPlaying(node.address),
          onPlayStop: () => _controller.isGroupPlaying(node.address)
              ? _controller.stopGroup(node.address)
              : _controller.playGroup(node.address),
          onMenu: (position) => _openRowMenu(node, position),
          onRegroupInto: (dragged) =>
              _controller.regroup(dragged, node.address),
        ),
        for (final child in node.children) ..._buildRows(child, depth + 1),
      ];
    }
    final address = node.address;
    return [
      _ClipRow(
        node: node,
        depth: depth,
        selected: _controller.editedAddress == address,
        playing: _controller.isPlaying(address),
        paused: _controller.isPaused(address),
        loop: _controller.loopOf(address),
        onSelect: () => _controller.select(address),
        onPlayStop: () =>
            _controller.isPlaying(address) || _controller.isPaused(address)
            ? _controller.stopClip(address)
            : _controller.playClip(address),
        onToggleLoop: () => _controller.toggleLoop(address),
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
      case _AddAction.newClip:
        _controller.newClip(group: group);
      case _AddAction.newGroup:
        _controller.newGroup(group: group);
    }
  }

  Future<void> _openRowMenu(ClipTreeNode node, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    // A clip's new-clip / new-group create a sibling (under its parent); a
    // group's create inside it. Duplicate is clip-only.
    final createGroup = node.isGroup ? node.address : node.address.parent;
    final actions = <_RowAction>[
      _RowAction.newClip,
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
      case _RowAction.newClip:
        _controller.newClip(group: createGroup);
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

  Future<void> _renameNode(ClipTreeNode node) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: node.name),
    );
    if (name == null || name.trim().isEmpty) return;
    _controller.rename(node.address, name);
  }

  Future<void> _deleteNode(ClipTreeNode node) async {
    final impact = _controller.impactOf(node.address);
    final what = node.isGroup ? 'group' : 'clip';
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
  newClip('new clip'),
  newGroup('new group');

  const _AddAction(this.label);

  final String label;
}

/// The per-row context-menu actions.
enum _RowAction {
  newClip('new clip'),
  newGroup('new group'),
  duplicate('duplicate'),
  rename('rename…'),
  delete('delete');

  const _RowAction(this.label);

  final String label;
}

/// The expanded panel header: the LIBRARY title, an add `+`, stop-all, and the
/// collapse toggle.
class _Header extends StatelessWidget {
  const _Header({
    required this.onAdd,
    required this.onStopAll,
    required this.onCollapse,
  });

  final VoidCallback onAdd;
  final VoidCallback onStopAll;
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
              'library'.toUpperCase(),
              style: PhiType.caption().copyWith(color: PhiColors.fg1),
            ),
          ),
          _IconButton(
            buttonKey: LibraryPanel.addMenuKey,
            icon: Icons.add,
            tooltip: 'new…',
            onTap: onAdd,
          ),
          _IconButton(
            buttonKey: LibraryPanel.stopAllKey,
            icon: Icons.stop,
            tooltip: 'stop all',
            onTap: onStopAll,
          ),
          _IconButton(
            buttonKey: LibraryPanel.expandToggleKey,
            icon: Icons.chevron_left,
            tooltip: 'hide library',
            onTap: onCollapse,
          ),
        ],
      ),
    );
  }
}

/// A group folder row — a drop target that re-parents a dragged node into it, a
/// subtree play / stop toggle, and a context menu.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.node,
    required this.depth,
    required this.playing,
    required this.onPlayStop,
    required this.onMenu,
    required this.onRegroupInto,
  });

  final ClipTreeNode node;
  final int depth;
  final bool playing;
  final VoidCallback onPlayStop;
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
          trailing: [
            _IconButton(
              buttonKey: LibraryPanel.groupPlayKey(node.address),
              icon: playing ? Icons.stop : Icons.play_arrow,
              tooltip: playing ? 'stop group' : 'play group',
              color: playing ? PhiColors.voice1 : PhiColors.fg2,
              onTap: onPlayStop,
            ),
          ],
        );
      },
    );
  }
}

/// A clip leaf row — tap to open in the editor, drag to reorder / regroup,
/// per-row play/stop and loop toggles, a playing dot, and a context menu.
class _ClipRow extends StatelessWidget {
  const _ClipRow({
    required this.node,
    required this.depth,
    required this.selected,
    required this.playing,
    required this.paused,
    required this.loop,
    required this.onSelect,
    required this.onPlayStop,
    required this.onToggleLoop,
    required this.onMenu,
    required this.onDropOnRow,
  });

  final ClipTreeNode node;
  final int depth;
  final bool selected;
  final bool playing;
  final bool paused;
  final bool loop;
  final VoidCallback onSelect;
  final VoidCallback onPlayStop;
  final VoidCallback onToggleLoop;
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
            trailing: [
              if (playing)
                Padding(
                  padding: const EdgeInsets.only(right: PhiSpacing.s0),
                  child: Icon(
                    Icons.circle,
                    key: LibraryPanel.playingDotKey(address),
                    size: 7,
                    color: PhiColors.voice1,
                  ),
                ),
              _IconButton(
                buttonKey: LibraryPanel.loopKey(address),
                icon: Icons.loop,
                tooltip: loop ? 'loop on' : 'loop off',
                color: loop ? PhiColors.voice2 : PhiColors.fg3,
                onTap: onToggleLoop,
              ),
              _IconButton(
                buttonKey: LibraryPanel.playKey(address),
                icon: playing || paused ? Icons.stop : Icons.play_arrow,
                tooltip: playing || paused ? 'stop' : 'play',
                color: playing || paused ? PhiColors.voice1 : PhiColors.fg2,
                onTap: onPlayStop,
              ),
            ],
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
        key: LibraryPanel.rowKey(address),
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
              buttonKey: LibraryPanel.menuKey(address),
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
          key: LibraryPanel.dragHandleKey(address),
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
    this.color = PhiColors.fg2,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Key? buttonKey;
  final Color color;

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
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }
}

/// The vertical LIBRARY label shown on the collapsed strip.
class _VerticalLabel extends StatelessWidget {
  const _VerticalLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'library'.toUpperCase(),
      style: PhiType.caption().copyWith(color: PhiColors.fg2),
    );
  }
}

/// The empty-tree hint shown when the `clip.` namespace has no clips yet.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PhiSpacing.s3),
      child: Text(
        'no clips yet — use + to add one',
        style: PhiType.monoS().copyWith(color: PhiColors.fg3),
      ),
    );
  }
}

/// Modal that renames a clip or group. Owns its [TextEditingController] so the
/// field's exit animation never outlives it (mirrors the chain panel's rename).
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
