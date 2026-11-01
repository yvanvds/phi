import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/multislider_stroke.dart';

void main() {
  test('the first point writes the cell under it', () {
    final stroke = MultisliderStroke(4);
    expect(stroke.moveTo(0.6, 0.3), {2: 0.3});
  });

  test('a swipe fills every cell it crossed, along the line', () {
    final stroke = MultisliderStroke(4)..moveTo(0.125, 0);
    final cells = stroke.moveTo(0.875, 1);
    expect(cells.keys, [1, 2, 3]);
    expect(cells[1], closeTo(1 / 3, 1e-9));
    expect(cells[2], closeTo(2 / 3, 1e-9));
    expect(cells[3], 1);
  });

  test('a swipe leftwards fills in the other direction', () {
    final stroke = MultisliderStroke(4)..moveTo(0.9, 0.5);
    expect(stroke.moveTo(0.1, 0.5).keys, [2, 1, 0]);
  });

  test('positions outside the bank clamp to its edges', () {
    final stroke = MultisliderStroke(4);
    expect(stroke.moveTo(-1, 2), {0: 1});
    expect(MultisliderStroke(4).moveTo(5, -1), {3: 0});
  });
}
