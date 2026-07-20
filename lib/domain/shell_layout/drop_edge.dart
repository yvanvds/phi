import 'split_axis.dart';

/// Which edge of a pane a tab was dropped on to split it (design
/// `docs/design/shell-layout.md` §2 — "drag a tab to a pane edge to split").
///
/// A drop on the [left]/[right] edge splits the pane along a [SplitAxis.row] (the
/// dropped surface lands beside it); [top]/[bottom] split along a
/// [SplitAxis.column]. A drop on the *centre* is a join, not an edge — that is a
/// separate operation, so it has no member here.
enum DropEdge {
  left,
  right,
  top,
  bottom;

  /// The axis a split triggered by a drop on this edge runs along — horizontal
  /// ([SplitAxis.row]) for the vertical edges, vertical ([SplitAxis.column]) for
  /// the horizontal ones.
  SplitAxis get axis => this == DropEdge.left || this == DropEdge.right
      ? SplitAxis.row
      : SplitAxis.column;

  /// Whether the dropped surface's new pane sits *before* the target in child
  /// order — true for [left]/[top] (the surface lands to the left of / above the
  /// target), false for [right]/[bottom].
  bool get placesBefore => this == DropEdge.left || this == DropEdge.top;
}
