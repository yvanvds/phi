import 'dart:math' as math;

import 'function_point.dart';
import 'slider_range.dart';

/// How a `.function`'s points map onto the pixels of its editor (issue #475).
///
/// The plot is [width] by [height] pixels with the origin top left. The y axis
/// is the object's `minimum maximum` [range], bottom to top. The x axis is the
/// **domain** the points span: from 0 (the engine folds a negative x onto 0)
/// to the last point's x — or [defaultDomain] while there is no point past 0
/// to span to.
///
/// Values read off a pixel are snapped to a step no finer than one pixel's
/// worth ([xStep], [yStep]), a power of ten, so a click lands on a number a
/// person would type (`500`, not `502.6315789`).
class FunctionView {
  FunctionView({
    required this.points,
    required this.range,
    required this.width,
    required this.height,
    this._domain,
  });

  /// The points, in ascending-x order, as the GUI value reports them.
  final List<FunctionPoint> points;

  /// The y range, from the creation arguments.
  final SliderRange range;

  /// The plot's width, in pixels.
  final double width;

  /// The plot's height, in pixels.
  final double height;

  /// The domain shown before any point lies past 0 — Max's default, 1000.
  static const double defaultDomain = 1000;

  /// How close, in pixels, a press must land to a point to take it.
  static const double hitRadius = 6;

  final double? _domain;

  /// The same plot over [points], keeping this view's [domain] — the view a
  /// drag works in, so moving the last point does not rescale the plot under
  /// the pointer.
  FunctionView withPoints(List<FunctionPoint> points) => FunctionView(
    points: points,
    range: range,
    width: width,
    height: height,
    domain: domain,
  );

  /// The right end of the x axis: fixed when the view was made with one,
  /// otherwise the last point's x.
  double get domain {
    final fixed = _domain;
    if (fixed != null && fixed > 0) return fixed;
    final last = points.isEmpty ? 0.0 : points.last.x;
    return last > 0 ? last : defaultDomain;
  }

  /// The x value step one pixel is worth, rounded down to a power of ten.
  double get xStep => _step(domain, width);

  /// The y value step one pixel is worth, rounded down to a power of ten.
  double get yStep => _step(range.high - range.low, height);

  /// The pixel column of [x].
  double xToPixel(double x) => width <= 0 ? 0 : x / domain * width;

  /// The pixel row of [y] (the range's top is row 0).
  double yToPixel(double y) => height * (1 - range.positionOf(y));

  /// The x under pixel column [px], snapped to [xStep]. Not clamped on the
  /// right — a drag past the edge reaches past the domain — but never below 0.
  double xAt(double px) {
    if (width <= 0) return 0;
    return math.max(0, snap(px / width * domain, xStep));
  }

  /// The y under pixel row [py], snapped to [yStep] and clamped to the range.
  double yAt(double py) {
    if (height <= 0) return range.low;
    final y = snap(range.valueAt(1 - py / height), yStep);
    return y.clamp(range.low, range.high);
  }

  /// The point within [hitRadius] of ([px], [py]), the nearest if several.
  int? pointAt(double px, double py) {
    int? best;
    var bestDistance = hitRadius;
    for (var i = 0; i < points.length; i++) {
      final dx = xToPixel(points[i].x) - px;
      final dy = yToPixel(points[i].y) - py;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= bestDistance) {
        best = i;
        bestDistance = d;
      }
    }
    return best;
  }

  /// The segment under pixel column [px], named by the point it arrives at
  /// (1 to `points.length - 1`) — the point whose curve shapes it. Null left
  /// of the first point, right of the last, or with fewer than two points.
  int? segmentAt(double px) {
    for (var i = 1; i < points.length; i++) {
      final left = xToPixel(points[i - 1].x);
      final right = xToPixel(points[i].x);
      if (px >= left && px <= right && right > left) return i;
    }
    return null;
  }

  /// [value] rounded to a multiple of [step], with the float noise of the
  /// multiplication trimmed away.
  static double snap(double value, double step) {
    if (!(step > 0)) return value;
    final decimals = math.max(0, -(math.log(step) / math.ln10).round());
    final snapped = (value / step).round() * step;
    return double.parse(snapped.toStringAsFixed(decimals));
  }

  static double _step(double span, double pixels) {
    if (!(span > 0) || !(pixels > 0)) return 0;
    final exponent = (math.log(span / pixels) / math.ln10).floor();
    return math.pow(10, exponent).toDouble();
  }
}
