import 'patch_args.dart';
import 'slider_range.dart';

/// A `.matrixctrl`'s creation arguments, `columns [rows] [minimum] [maximum]`
/// (issue #474).
///
/// Read the way `gMatrixCtrl::ShapeGrid` reads them: tokens that are not
/// numbers are skipped, the first two numbers are the column and row counts
/// (truncated, clamped to 1–256, default 8 each) and the next two the cell
/// range (default 0 and 1). The range is an ordered pair, as the engine bounds
/// against the sorted two, so [range] is always low to high.
///
/// The grid is flattened **column-major**, as the engine's GUI value is: cell
/// (`column`, `row`) is at `column * rows + row` ([indexOf]).
class MatrixctrlArgs {
  const MatrixctrlArgs({
    required this.columns,
    required this.rows,
    required this.range,
  });

  /// Parse [args]. Anything missing keeps its engine default.
  factory MatrixctrlArgs.parse(String args) {
    final numbers = [for (final t in splitPatchArgs(args)) ?double.tryParse(t)];
    int axis(int i) {
      if (i >= numbers.length) return defaultAxis;
      final n = numbers[i];
      // `ExprToInt`: truncate, and a value it cannot hold becomes 0.
      final whole = n.isFinite && n.abs() < 2147483648 ? n.truncate() : 0;
      return whole.clamp(minAxis, maxAxis);
    }

    double bound(int i, double fallback) =>
        i < numbers.length ? numbers[i] : fallback;
    return MatrixctrlArgs(
      columns: axis(0),
      rows: axis(1),
      range: SliderRange(bound(2, 0), bound(3, 1)),
    );
  }

  /// The engine's default column (and row) count.
  static const int defaultAxis = 8;

  /// The fewest columns (or rows) a grid has.
  static const int minAxis = 1;

  /// The most columns (or rows) a grid has (`gMatrixCtrl::MAX_AXIS`).
  static const int maxAxis = 256;

  /// How many columns the grid has, left to right.
  final int columns;

  /// How many rows the grid has, top to bottom.
  final int rows;

  /// The span every cell is clamped into.
  final SliderRange range;

  /// How many cells the grid has.
  int get cellCount => columns * rows;

  /// Whether a cell holds more than on and off: the range reaches above 1, so
  /// a vertical drag steps the value in whole units and the cell shows it as a
  /// fill level.
  bool get stepped => range.high > 1;

  /// The flat index of cell ([column], [row]).
  int indexOf(int column, int row) => column * rows + row;

  /// The column of the cell at flat [index].
  int columnOf(int index) => index ~/ rows;

  /// The row of the cell at flat [index].
  int rowOf(int index) => index % rows;
}
