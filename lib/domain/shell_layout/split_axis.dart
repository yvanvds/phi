/// The axis a split arranges its child panes along (design
/// `docs/design/shell-layout.md` §2 — "rows and columns of panes").
///
/// A [row] lays its children out horizontally (left → right); a [column] stacks
/// them vertically (top → bottom). Serialised by [name] in the layout section,
/// so the identifiers are part of the on-disk contract.
enum SplitAxis {
  /// Children sit side by side, left to right — a row of panes.
  row,

  /// Children stack top to bottom — a column of panes.
  column,
}
