import 'matrixctrl_args.dart';

/// One pointer on a `.matrixctrl` grid: which cells each move writes, and with
/// what value (issue #474).
///
/// Positions are in the grid's own pixels, `width` by `height`, with column 0
/// on the left and row 0 at the top. Every answer is the cells to write as
/// flat index → value in the object's units, in the order to send them.
///
/// - **On/off grid** (a range that tops out at 1 or below): the press toggles
///   the cell under it — a cell above the minimum goes to the minimum, any
///   other to the maximum — and dragging paints that same value onto every
///   cell the pointer crosses, so a swipe draws a line of steps.
/// - **Stepped grid** ([MatrixctrlArgs.stepped]): a press that first moves
///   mostly vertically, by a step's travel, steps the pressed cell one whole
///   unit per [stepPixels] (up raises it) inside the range, wherever the
///   pointer then goes. A press that first leaves its cell sideways paints the
///   toggled value, as on an on/off grid, and a press that does neither
///   toggles the cell on release — a click.
class MatrixGesture {
  /// A gesture over a grid of [args]'s shape, drawn [width] by [height].
  MatrixGesture({
    required this.args,
    required this.width,
    required this.height,
  });

  /// The grid's shape and range.
  final MatrixctrlArgs args;

  /// The grid's drawn width, in pixels.
  final double width;

  /// The grid's drawn height, in pixels.
  final double height;

  /// How far a vertical drag travels for one whole step of a stepped cell.
  static const double stepPixels = 6;

  _Mode _mode = _Mode.idle;
  int _pressed = 0;
  double _startValue = 0;
  double _startX = 0;
  double _startY = 0;
  double _stepValue = 0;
  double _paint = 0;
  (int, int)? _last;
  final Set<int> _painted = {};

  /// The cell under ([x], [y]) as (column, row), clamped onto the grid.
  (int, int) cellAt(double x, double y) {
    int along(double at, double extent, int count) {
      if (!(extent > 0)) return 0;
      return (at / extent * count).floor().clamp(0, count - 1);
    }

    return (along(x, width, args.columns), along(y, height, args.rows));
  }

  /// The value a click turns [value] into: the minimum from anything above
  /// it, the maximum otherwise.
  double toggled(double value) =>
      value > args.range.low ? args.range.low : args.range.high;

  /// The pointer went down at ([x], [y]) on a cell now holding [current].
  Map<int, double> down(double x, double y, double current) {
    final (column, row) = cellAt(x, y);
    _pressed = args.indexOf(column, row);
    _startValue = current;
    _stepValue = current;
    _startX = x;
    _startY = y;
    _last = (column, row);
    _painted.clear();
    if (args.stepped) {
      _mode = _Mode.pending;
      return const {};
    }
    _mode = _Mode.paint;
    _paint = toggled(current);
    _painted.add(_pressed);
    return {_pressed: _paint};
  }

  /// The pointer moved to ([x], [y]).
  Map<int, double> moveTo(double x, double y) {
    final here = cellAt(x, y);
    switch (_mode) {
      case _Mode.idle:
        return const {};
      case _Mode.pending:
        // Mostly vertical and a step's travel: this is a step drag, even if
        // the first move the pointer reports is already over a neighbour.
        final dy = (_startY - y).abs();
        if (dy >= stepPixels && dy > (_startX - x).abs()) {
          _mode = _Mode.step;
          return _stepTo(y);
        }
        if (here == _last) return const {};
        // Left the cell sideways before stepping it: a paint stroke.
        _mode = _Mode.paint;
        _paint = toggled(_startValue);
        _painted.add(_pressed);
        return {_pressed: _paint, ..._paintTo(here)};
      case _Mode.step:
        return _stepTo(y);
      case _Mode.paint:
        return _paintTo(here);
    }
  }

  /// The pointer lifted. A stepped press that neither stepped nor painted is a
  /// click, and toggles its cell now.
  Map<int, double> up() {
    final click = _mode == _Mode.pending;
    _mode = _Mode.idle;
    return click ? {_pressed: toggled(_startValue)} : const {};
  }

  Map<int, double> _stepTo(double y) {
    final steps = ((_startY - y) / stepPixels).truncate();
    final range = args.range;
    final value = (_startValue + steps).clamp(range.low, range.high);
    if (value == _stepValue) return const {};
    _stepValue = value;
    return {_pressed: value};
  }

  /// Paint every cell on the straight line from the last cell to [here] that
  /// this stroke has not painted yet, so a quick swipe leaves no gaps.
  Map<int, double> _paintTo((int, int) here) {
    final from = _last ?? here;
    _last = here;
    final (c0, r0) = from;
    final (c1, r1) = here;
    final dc = c1 - c0;
    final dr = r1 - r0;
    final n = dc.abs() > dr.abs() ? dc.abs() : dr.abs();
    final cells = <int, double>{};
    for (var i = 1; i <= n; i++) {
      final column = c0 + (dc * i / n).round();
      final row = r0 + (dr * i / n).round();
      final index = args.indexOf(column, row);
      if (_painted.add(index)) cells[index] = _paint;
    }
    return cells;
  }
}

enum _Mode { idle, pending, step, paint }
