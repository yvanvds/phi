import 'dart:math' as math;

/// The geometry of a `.preset` slot grid (issue #477): [slots] buttons laid
/// out row by row, slot 0 at the top left, sharing a box of [width] by
/// [height] equally — so a bank of any size fits the box it was given.
///
/// Pure maths, shared by the painter (where each slot is drawn) and the body
/// (which slot a click landed on).
class PresetGrid {
  PresetGrid({required this.slots, required this.width, required this.height})
    : columns = columnsFor(slots),
      rows = rowsFor(slots);

  /// How many slots the bank holds.
  final int slots;

  /// The box the grid fills.
  final double width;
  final double height;

  /// Slots per row, and rows.
  final int columns;
  final int rows;

  /// The narrowest a grid of more than a row lays out: eight slots per row,
  /// so the default 32 is four rows of eight.
  static const int minColumns = 8;

  /// Slots per row for a bank of [slots]: one row up to [minColumns], then
  /// [minColumns] wide until the grid would be taller than it is wide, and
  /// square beyond that — so 1024 slots is 32 by 32, not 128 rows.
  static int columnsFor(int slots) {
    if (slots <= minColumns) return math.max(1, slots);
    return math.max(minColumns, math.sqrt(slots).ceil());
  }

  /// Rows for a bank of [slots], at [columnsFor] slots per row.
  static int rowsFor(int slots) {
    final columns = columnsFor(slots);
    return math.max(1, (slots + columns - 1) ~/ columns);
  }

  /// One slot's width and height.
  double get cellWidth => width / columns;
  double get cellHeight => height / rows;

  /// The slot under the point ([x], [y]) in the box, or null off the grid —
  /// outside the box, or in the unused tail of the last row.
  int? slotAt(double x, double y) {
    if (width <= 0 || height <= 0) return null;
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final column = math.min(columns - 1, x ~/ cellWidth);
    final row = math.min(rows - 1, y ~/ cellHeight);
    final slot = row * columns + column;
    return slot < slots ? slot : null;
  }

  /// The top-left corner of [slot]'s cell.
  (double, double) originOf(int slot) =>
      ((slot % columns) * cellWidth, (slot ~/ columns) * cellHeight);
}
