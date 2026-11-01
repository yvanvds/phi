import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/slider_range.dart';

void main() {
  test('defaults to the engine bounds, 0 to 127', () {
    final range = SliderRange.fromArgs('');
    expect(range.low, 0);
    expect(range.high, 127);
  });

  test('reads a pair at an offset, and sorts a reversed one', () {
    final range = SliderRange.fromArgs('0 1 10 -10', at: 2);
    expect(range.low, -10);
    expect(range.high, 10);
  });

  test('an unparseable bound keeps its default', () {
    final range = SliderRange.fromArgs('x 50');
    expect(range.low, 0);
    expect(range.high, 50);
  });

  test('maps values to positions and back, clamped', () {
    final range = SliderRange(20, 220);
    expect(range.positionOf(120), 0.5);
    expect(range.positionOf(-5), 0);
    expect(range.positionOf(999), 1);
    expect(range.valueAt(0.25), 70);
    expect(range.valueAt(2), 220);
  });

  test('a zero-width span puts everything at 0', () {
    expect(SliderRange(5, 5).positionOf(5), 0);
    expect(SliderRange(0, 1).positionOf(double.nan), 0);
  });

  test('formats a number for a message without trailing zeros', () {
    expect(SliderRange.format(63.5), '63.5');
    expect(SliderRange.format(127), '127');
    expect(SliderRange.format(0.1234567), '0.123457');
    expect(SliderRange.format(-0.0000001), '0');
  });
}
