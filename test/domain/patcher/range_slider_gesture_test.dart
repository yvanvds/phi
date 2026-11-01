import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/range_slider_gesture.dart';

void main() {
  RangeSliderGesture press(double at) =>
      RangeSliderGesture.start(low: 0.25, high: 0.75, at: at, grabRadius: 0.05);

  test('a press near an end takes that end', () {
    final g = press(0.73);
    expect(g.movesBoth, isFalse);
    g.update(0.9);
    expect(g.low, 0.25);
    expect(g.high, 0.9);
  });

  test('an end dragged past the other becomes the other side', () {
    final g = press(0.26)..update(0.9);
    expect(g.low, 0.75);
    expect(g.high, 0.9);
  });

  test(
    'a press inside the span slides the whole range, stopping at the bounds',
    () {
      final g = press(0.5);
      expect(g.movesBoth, isTrue);
      expect(
        (g.low, g.high),
        (0.25, 0.75),
        reason: 'a press alone moves nothing',
      );
      g.update(0.6);
      expect(g.low, closeTo(0.35, 1e-9));
      expect(g.high, closeTo(0.85, 1e-9));
      g.update(1);
      expect(g.low, closeTo(0.5, 1e-9));
      expect(g.high, 1);
      // The grabbed point stays under the pointer: overshoot past the wall is
      // not stored, so the range leaves the wall once the pointer is back.
      g.update(0.9);
      expect(g.high, 1);
      g.update(0.65);
      expect(g.high, closeTo(0.9, 1e-9));
    },
  );

  test('a press outside the span moves the nearer end there', () {
    final g = press(0.1);
    expect(g.low, 0.1);
    expect(g.high, 0.75);
  });

  test('a collapsed range opens towards the side pressed', () {
    final up = RangeSliderGesture.start(
      low: 0.5,
      high: 0.5,
      at: 0.5,
      grabRadius: 0.05,
    )..update(0.8);
    expect((up.low, up.high), (0.5, 0.8));
  });
}
