/// The drag maths of a `.rslider`: which part of the range a press takes hold
/// of, and where the two ends go as the pointer moves (issue #472).
///
/// Everything is a 0–1 position along the bar. A press within [grabRadius] of
/// an end takes that end, and the end then follows the pointer — past the
/// other end too, which simply makes it the top of the range, the way the
/// engine sorts its ends on the way out. A press inside the span takes the
/// whole range and slides it, keeping its width and stopping at the bounds. A
/// press outside the span moves the nearer end there and takes it.
class RangeSliderGesture {
  /// Start a gesture on the range [low]–[high] with a press at [at].
  RangeSliderGesture.start({
    required double low,
    required double high,
    required double at,
    required double grabRadius,
  }) : _low = low,
       _high = high {
    final p = at.clamp(0.0, 1.0);
    final toLow = (p - low).abs();
    final toHigh = (p - high).abs();
    final nearEnd = toLow <= grabRadius || toHigh <= grabRadius;
    if (!nearEnd && p > low && p < high) {
      _anchor = p;
      return;
    }
    // The nearer end; on a tie (a collapsed range) the side the press is on.
    final takeHigh = toHigh < toLow || (toHigh == toLow && p >= high);
    _fixed = takeHigh ? low : high;
    update(p);
  }

  double _low;
  double _high;

  /// The end that stays put while the other follows the pointer — null when
  /// the whole range is held.
  double? _fixed;

  /// Where the pointer was when the whole range was last moved — null when an
  /// end is held.
  double? _anchor;

  /// Whether the press took the whole range rather than one end.
  bool get movesBoth => _anchor != null;

  /// The lower end, 0–1.
  double get low => _low;

  /// The upper end, 0–1.
  double get high => _high;

  /// The pointer moved to [at].
  void update(double at) {
    final p = at.clamp(0.0, 1.0);
    final fixed = _fixed;
    if (fixed != null) {
      _low = p < fixed ? p : fixed;
      _high = p < fixed ? fixed : p;
      return;
    }
    final anchor = _anchor!;
    var delta = p - anchor;
    if (_low + delta < 0) delta = -_low;
    if (_high + delta > 1) delta = 1 - _high;
    _low += delta;
    _high += delta;
    _anchor = anchor + delta;
  }
}
