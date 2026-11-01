import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/function_args.dart';
import 'package:phi/domain/patcher/function_edit.dart';
import 'package:phi/domain/patcher/function_gesture.dart';
import 'package:phi/domain/patcher/function_point.dart';
import 'package:phi/domain/patcher/function_view.dart';

void main() {
  final args = FunctionArgs.parse('');

  FunctionGesture over(List<FunctionPoint> points, {FunctionArgs? with_}) =>
      FunctionGesture(
        view: FunctionView(
          points: points,
          range: (with_ ?? args).range,
          width: 200,
          height: 100,
        ),
        args: with_ ?? args,
      );

  const three = [
    FunctionPoint(0, 0),
    FunctionPoint(500, 1),
    FunctionPoint(1000, 0),
  ];

  test('a press on empty space adds a point, and the drag then moves it', () {
    final g = over(const []);
    expect(g.down(100, 50), const FunctionEdit.add(500, 0.5));
    expect(g.pressedPoint, isFalse);
    g.adopt(const [FunctionPoint(500, 0.5)], 0);
    expect(g.selected, 0);
    // The domain the press saw is held, so the pixels keep their meaning.
    expect(g.domain, 1000);
    expect(g.moveTo(120, 20), const FunctionEdit.move(0, 600, 0.8));
    expect(g.moveTo(120, 20), isNull, reason: 'nothing changed');
  });

  test('a refused add leaves the gesture idle', () {
    final g = over(const []);
    g.down(100, 50);
    g.adopt(const [], null);
    expect(g.moveTo(120, 20), isNull);
  });

  test('a full store adds nothing', () {
    final g = over(const [
      FunctionPoint(0, 0),
      FunctionPoint(1000, 1),
    ], with_: FunctionArgs.parse('2'));
    expect(g.down(100, 50), isNull);
  });

  test('a press on a point takes it, and a drag keeps it between its '
      'neighbours', () {
    final g = over(three);
    expect(g.down(100, 0), isNull);
    expect(g.pressedPoint, isTrue);
    expect(g.selected, 1);
    expect(g.moveTo(250, 0), const FunctionEdit.move(1, 999, 1));
    expect(g.moveTo(-50, 100), const FunctionEdit.move(1, 1, 0));
  });

  test(
    'the last point may be dragged past the edge, the first not below 0',
    () {
      final g = over(three);
      g.down(200, 100);
      expect(g.moveTo(240, 100), const FunctionEdit.move(2, 1200, 0));
      final first = over(three)..down(0, 100);
      expect(first.moveTo(-40, 100), isNull, reason: 'already at 0');
    },
  );

  test('an alt-drag bends the segment upwards, whichever way it runs', () {
    final rising = over(three);
    expect(rising.down(50, 60, alt: true), isNull);
    expect(rising.selected, 1);
    expect(rising.moveTo(50, 10), const FunctionEdit.curve(1, -0.5));
    expect(rising.moveTo(50, -500), const FunctionEdit.curve(1, -1));

    final falling = over(three)..down(150, 60, alt: true);
    expect(falling.moveTo(150, 10), const FunctionEdit.curve(2, 0.5));
  });

  test('an alt-press outside every segment does nothing', () {
    final g = over(const [FunctionPoint(500, 1)]);
    expect(g.down(50, 50, alt: true), isNull);
    expect(g.moveTo(50, 0), isNull);
  });

  test('finds an added point by its x, allowing for float rounding', () {
    const points = [FunctionPoint(0, 0), FunctionPoint(0.30000001, 1)];
    expect(FunctionGesture.indexOfX(points, 0.3), 1);
    expect(FunctionGesture.indexOfX(points, 0.5), isNull);
  });
}
