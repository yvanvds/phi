import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_motion.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_spacing.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/shell_layout/layout_node.dart';
import 'tab_drag_data.dart';

/// The tab strip along the top of a pane (design `docs/design/shell-layout.md`
/// §2 — "each pane holds a tab stack of surfaces"). It renders one chip per tab
/// with the active one accented, and wires the four tab interactions:
///
/// - **select** — a tap on a chip ([onSelect]).
/// - **close** — the chip's `×` ([onClose]); the surface returns to the closed
///   set (the rail summons it back).
/// - **reorder** — dragging a chip onto another chip in the *same* pane drops it
///   before that chip ([onReorder], indices already resolved for the domain's
///   remove-then-insert).
/// - **cross-pane join** — dragging a chip from *another* pane onto a chip (or
///   the strip's free space) inserts it there ([onJoinAt]).
///
/// Each chip is a [Draggable] carrying a [TabDragData]; the same drag can also
/// leave the strip and land on a pane edge/centre (handled by the dock zones),
/// so an invalid release just snaps back. Overflow on a narrow pane scrolls
/// horizontally rather than clipping.
class PaneTabStrip extends StatelessWidget {
  const PaneTabStrip({
    required this.pane,
    required this.isActivePane,
    required this.labelFor,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
    required this.onJoinAt,
    super.key,
  });

  /// The pane whose tab stack this strip shows.
  final LayoutPane pane;

  /// Whether this pane is the focused one — its active tab gets the hot accent;
  /// an unfocused pane's active tab reads in a quieter foreground.
  final bool isActivePane;

  /// Maps a surface id to the human label shown on its chip.
  final String Function(String surfaceId) labelFor;

  /// Selects the tab (foreground it + focus this pane).
  final ValueChanged<String> onSelect;

  /// Closes the tab, returning its surface to the summonable closed set.
  final ValueChanged<String> onClose;

  /// Reorders within this pane: move the tab at `from` to land at `to` — indices
  /// already resolved to the domain's remove-then-insert convention.
  final void Function(int from, int to) onReorder;

  /// Drops a tab dragged in from another pane, inserting it at `at` (the strip
  /// end when `at` is the tab count).
  final void Function(TabDragData data, int at) onJoinAt;

  /// The strip's fixed height — a compact chrome band above the surface.
  static const double height = 28;

  /// Test handle for a tab chip in a given pane.
  static Key tabKey(String paneId, String surfaceId) =>
      ValueKey('tab-$paneId-$surfaceId');

  /// Test handle for a tab's close affordance.
  static Key closeKey(String paneId, String surfaceId) =>
      ValueKey('tab-close-$paneId-$surfaceId');

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: PhiColors.bg1,
        border: Border(bottom: BorderSide(color: PhiColors.line1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < pane.tabs.length; i++)
              _Tab(
                key: tabKey(pane.id, pane.tabs[i]),
                paneId: pane.id,
                surfaceId: pane.tabs[i],
                label: labelFor(pane.tabs[i]),
                index: i,
                selected: pane.tabs[i] == pane.active,
                isActivePane: isActivePane,
                onSelect: () => onSelect(pane.tabs[i]),
                onClose: () => onClose(pane.tabs[i]),
                onDropOnTab: (data) => _dropOnTab(data, i),
              ),
            // Free space past the last tab accepts a drop = insert at the end.
            _TrailingDropZone(onDrop: (data) => _dropAtEnd(data)),
          ],
        ),
      ),
    );
  }

  /// Resolves a drop of [data] onto the tab at [targetIndex] ("insert before
  /// this tab"). Within the pane it becomes a reorder with the index shifted for
  /// the domain's remove-then-insert; from another pane it is a join at that
  /// slot.
  void _dropOnTab(TabDragData data, int targetIndex) {
    if (data.sourcePaneId == pane.id) {
      final from = pane.tabs.indexOf(data.surfaceId);
      if (from < 0 || from == targetIndex) return;
      final to = from < targetIndex ? targetIndex - 1 : targetIndex;
      onReorder(from, to);
    } else {
      onJoinAt(data, targetIndex);
    }
  }

  /// Resolves a drop on the strip's free space = insert at the end.
  void _dropAtEnd(TabDragData data) {
    if (data.sourcePaneId == pane.id) {
      final from = pane.tabs.indexOf(data.surfaceId);
      if (from < 0 || from == pane.tabs.length - 1) return;
      onReorder(from, pane.tabs.length - 1);
    } else {
      onJoinAt(data, pane.tabs.length);
    }
  }
}

/// One tab chip: a draggable, tappable label with a close affordance, that is
/// also a drop target for another chip (reorder / cross-pane insert).
class _Tab extends StatelessWidget {
  const _Tab({
    required this.paneId,
    required this.surfaceId,
    required this.label,
    required this.index,
    required this.selected,
    required this.isActivePane,
    required this.onSelect,
    required this.onClose,
    required this.onDropOnTab,
    super.key,
  });

  final String paneId;
  final String surfaceId;
  final String label;
  final int index;
  final bool selected;
  final bool isActivePane;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<TabDragData> onDropOnTab;

  @override
  Widget build(BuildContext context) {
    final data = TabDragData(surfaceId: surfaceId, sourcePaneId: paneId);
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (details) => details.data.surfaceId != surfaceId,
      onAcceptWithDetails: (details) => onDropOnTab(details.data),
      builder: (context, candidate, rejected) {
        final showCaret = candidate.isNotEmpty;
        return Draggable<TabDragData>(
          data: data,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _TabFeedback(label: label),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _chip(insertionCaret: false),
          ),
          child: _chip(insertionCaret: showCaret),
        );
      },
    );
  }

  Widget _chip({required bool insertionCaret}) {
    final accent = selected && isActivePane;
    final bg = selected ? PhiColors.bg2 : PhiColors.bg1;
    final fg = accent
        ? PhiColors.voice1
        : (selected ? PhiColors.fg0 : PhiColors.fg2);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSelect,
        child: AnimatedContainer(
          duration: PhiMotion.dur1,
          curve: PhiMotion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: PhiSpacing.s2),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              // A left caret marks where a dragged tab would land.
              left: BorderSide(
                color: insertionCaret ? PhiColors.voice1 : PhiColors.line1,
                width: insertionCaret ? 2 : 1,
              ),
              bottom: BorderSide(
                color: accent ? PhiColors.voice1 : PhiColors.line0,
                width: accent ? 2 : 0,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: PhiType.monoS().copyWith(color: fg)),
              const SizedBox(width: PhiSpacing.s2),
              GestureDetector(
                key: PaneTabStrip.closeKey(paneId, surfaceId),
                onTap: onClose,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    '×',
                    style: PhiType.monoS().copyWith(color: PhiColors.fg3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating chip shown under the pointer while a tab is dragged.
class _TabFeedback extends StatelessWidget {
  const _TabFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PhiSpacing.s2,
          vertical: PhiSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: PhiColors.bg3,
          border: Border.all(color: PhiColors.lineHot),
          borderRadius: PhiRadii.all1,
        ),
        child: Text(
          label,
          style: PhiType.monoS().copyWith(color: PhiColors.fg0),
        ),
      ),
    );
  }
}

/// The strip's free space after the last tab — a drop here appends.
class _TrailingDropZone extends StatelessWidget {
  const _TrailingDropZone({required this.onDrop});

  final ValueChanged<TabDragData> onDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TabDragData>(
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidate, rejected) => Container(
        width: PhiSpacing.s7,
        color: candidate.isEmpty ? null : PhiColors.line1,
      ),
    );
  }
}
