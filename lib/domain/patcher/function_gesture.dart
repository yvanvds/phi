import 'function_args.dart';
import 'function_edit.dart';
import 'function_point.dart';
import 'function_view.dart';

/// One pointer on a `.function`'s breakpoint editor: which edits each move
/// sends (issue #475).
///
/// Positions are in the plot's own pixels ([FunctionView]).
///
/// - A press on a point **takes** it, and dragging moves it. A point stays
///   strictly between its neighbours, so it keeps its index for the whole
///   drag — the engine re-sorts a moved point, and two points at one x would
///   merge into one. Only the last point may be dragged past the right edge,
///   which widens the domain.
/// - A press on empty space **adds** a point there (unless the store is
///   full); the caller sends it, reads the points back, and hands over its
///   index with [adopt], after which the drag moves it like any other.
/// - An **alt**-press over a segment bends it: dragging up bulges the segment
///   upwards, whichever way it runs, [bendPixels] of travel for a whole unit
///   of curve.
///
/// [selected] is the point the last press took or added — the one a Delete
/// key removes.
class FunctionGesture {
  /// A gesture over [view] on a function built from [args].
  FunctionGesture({required this._view, required this.args});

  /// The function's capacity and range.
  final FunctionArgs args;

  FunctionView _view;

  /// Vertical travel, in pixels, for a curve change of 1.
  static const double bendPixels = 100;

  _Mode _mode = _Mode.idle;
  int _index = 0;
  double _startPy = 0;
  double _startCurve = 0;
  double _sign = 1;
  FunctionPoint? _last;
  bool _hit = false;
  int? _selected;

  /// The right end of the x axis this gesture works over — the domain at the
  /// press, held while the pointer is down.
  double get domain => _view.domain;

  /// The point the last press took or added, or null.
  int? get selected => _selected;

  /// Whether the last press landed on a point that already existed.
  bool get pressedPoint => _hit;

  /// The pointer went down at ([px], [py]); [alt] is whether Alt was held.
  /// Answers the point to add, or null when the press adds nothing.
  FunctionEdit? down(double px, double py, {bool alt = false}) {
    final points = _view.points;
    _hit = false;
    if (alt) {
      final segment = _view.segmentAt(px);
      if (segment == null) {
        _mode = _Mode.idle;
        return null;
      }
      _mode = _Mode.bend;
      _index = segment;
      _startPy = py;
      _startCurve = points[segment].curve;
      _sign = points[segment].y > points[segment - 1].y ? -1 : 1;
      _selected = segment;
      return null;
    }
    final hit = _view.pointAt(px, py);
    if (hit != null) {
      _mode = _Mode.move;
      _index = hit;
      _last = points[hit];
      _hit = true;
      _selected = hit;
      return null;
    }
    if (points.length >= args.capacity) {
      _mode = _Mode.idle;
      return null;
    }
    _mode = _Mode.adding;
    return FunctionEdit.add(_view.xAt(px), _view.yAt(py));
  }

  /// After an add: the [points] as read back, and the new point's [index] in
  /// them (null when the engine refused it). The drag then moves that point,
  /// over the domain the press saw.
  void adopt(List<FunctionPoint> points, int? index) {
    final view = _view = _view.withPoints(points);
    if (_mode != _Mode.adding) return;
    if (index == null || index >= view.points.length) {
      _mode = _Mode.idle;
      return;
    }
    _mode = _Mode.move;
    _index = index;
    _last = view.points[index];
    _selected = index;
  }

  /// The pointer moved to ([px], [py]). Answers the edit to send, or null when
  /// nothing changed.
  FunctionEdit? moveTo(double px, double py) {
    switch (_mode) {
      case _Mode.idle:
      case _Mode.adding:
        return null;
      case _Mode.move:
        return _moveTo(px, py);
      case _Mode.bend:
        final travel = (_startPy - py) / bendPixels * _sign;
        final curve = FunctionView.snap(
          (_startCurve + travel).clamp(-1.0, 1.0),
          0.01,
        );
        final current = _view.points[_index].curve;
        if (curve == current) return null;
        _view = _withPoint(
          _index,
          FunctionPoint(_view.points[_index].x, _view.points[_index].y, curve),
        );
        return FunctionEdit.curve(_index, curve);
    }
  }

  /// The index of the point at [x] in [points] — how a caller finds the point
  /// it just added once the engine has sorted it in. The engine stores single
  /// precision floats, so the match allows for their rounding.
  static int? indexOfX(List<FunctionPoint> points, double x) {
    final tolerance = 1e-5 * (x.abs() > 1 ? x.abs() : 1);
    for (var i = 0; i < points.length; i++) {
      if ((points[i].x - x).abs() <= tolerance) return i;
    }
    return null;
  }

  /// The pointer lifted.
  void up() => _mode = _Mode.idle;

  FunctionEdit? _moveTo(double px, double py) {
    final points = _view.points;
    final step = _view.xStep > 0 ? _view.xStep : 1e-6;
    var x = _view.xAt(px);
    final low = _index > 0 ? points[_index - 1].x + step : 0.0;
    final high = _index < points.length - 1
        ? points[_index + 1].x - step
        : double.infinity;
    if (low <= high) {
      x = x.clamp(low, high);
    } else {
      x = points[_index].x;
    }
    final y = _view.yAt(py);
    final last = _last;
    if (last != null && last.x == x && last.y == y) return null;
    final moved = FunctionPoint(x, y, points[_index].curve);
    _last = moved;
    _view = _withPoint(_index, moved);
    return FunctionEdit.move(_index, x, y);
  }

  /// The view with point [index] replaced, the domain kept as it was at the
  /// press.
  FunctionView _withPoint(int index, FunctionPoint point) =>
      _view.withPoints([..._view.points]..[index] = point);
}

enum _Mode { idle, adding, move, bend }
