/// The payload a dragged tab carries while it is in flight (design
/// `docs/design/shell-layout.md` §2 — "drag a tab to a pane edge to split, to a
/// pane centre to join, within a stack to reorder").
///
/// It names the surface being moved and the pane it started in, so a drop can
/// tell a **reorder** (same [sourcePaneId]) from a **cross-pane move** and route
/// to the right layout operation. It is an opaque value — no Flutter, no engine —
/// so the drop-zone widgets stay trivially testable.
class TabDragData {
  const TabDragData({required this.surfaceId, required this.sourcePaneId});

  /// The surface id (a `SurfaceId.name`) of the tab being dragged.
  final String surfaceId;

  /// The id of the pane the drag started from.
  final String sourcePaneId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabDragData &&
          other.surfaceId == surfaceId &&
          other.sourcePaneId == sourcePaneId;

  @override
  int get hashCode => Object.hash(surfaceId, sourcePaneId);

  @override
  String toString() => 'TabDragData($surfaceId from $sourcePaneId)';
}
