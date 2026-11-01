/// A pointer drawing across a `.multislider`: which cells each move writes,
/// and what (issue #472).
///
/// Positions are 0–1 fractions of the bank — `x` across it, `y` the value
/// (0 at the bottom). The first point writes the cell under it; every later one
/// writes each cell between the previous point and itself, at the value the
/// straight line between the two crosses that cell's centre, so a quick swipe
/// leaves no gaps behind it.
class MultisliderStroke {
  /// A stroke over a bank of [count] cells.
  MultisliderStroke(this.count);

  /// How many cells the bank has.
  final int count;

  double? _lastX;
  double? _lastY;

  /// The cell under [x].
  int cellAt(double x) =>
      (x.clamp(0.0, 1.0) * count).floor().clamp(0, count - 1);

  /// The pointer is at ([x], [y]): the cells to write, by index, with their
  /// 0–1 values.
  Map<int, double> moveTo(double x, double y) {
    final value = y.clamp(0.0, 1.0);
    final lastX = _lastX;
    final lastY = _lastY;
    _lastX = x;
    _lastY = value;
    if (count <= 0) return const {};
    final here = cellAt(x);
    if (lastX == null || lastY == null) return {here: value};
    final from = cellAt(lastX);
    if (from == here) return {here: value};
    final step = here > from ? 1 : -1;
    final cells = <int, double>{};
    for (var i = from + step; i != here + step; i += step) {
      final centre = (i + 0.5) / count;
      final t = x == lastX
          ? 1.0
          : ((centre - lastX) / (x - lastX)).clamp(0.0, 1.0);
      cells[i] = i == here ? value : lastY + (value - lastY) * t;
    }
    return cells;
  }
}
