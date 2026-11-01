import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/matrix_gesture.dart';
import 'package:phi/domain/patcher/matrixctrl_args.dart';

void main() {
  // A 4 x 4 grid drawn 40 px square: 10 px cells.
  MatrixGesture over(String args) =>
      MatrixGesture(args: MatrixctrlArgs.parse(args), width: 40, height: 40);

  test('finds the cell under a point, clamped onto the grid', () {
    final g = over('4 4');
    expect(g.cellAt(15, 35), (1, 3));
    expect(g.cellAt(-5, 99), (0, 3));
  });

  group('an on/off grid', () {
    test('a press toggles the cell, and a lift writes nothing more', () {
      final g = over('4 4');
      expect(g.down(15, 5, 0), {4: 1.0});
      expect(g.up(), isEmpty);
      final h = over('4 4');
      expect(h.down(15, 5, 1), {4: 0.0}, reason: 'on turns off');
    });

    test('a drag paints the toggled value along its line, once per cell', () {
      final g = over('4 4');
      expect(g.down(5, 5, 0), {0: 1.0});
      // A jump from (0, 0) to (3, 3) fills the diagonal between.
      expect(g.moveTo(35, 35), {5: 1.0, 10: 1.0, 15: 1.0});
      expect(g.moveTo(35, 35), isEmpty);
      expect(g.moveTo(5, 5), isEmpty, reason: 'already painted');
    });
  });

  group('a stepped grid', () {
    test('a click toggles on release', () {
      final g = over('4 4 0 4');
      expect(g.down(5, 5, 2), isEmpty);
      expect(g.up(), {0: 0.0});
      final h = over('4 4 0 4');
      h.down(5, 5, 0);
      expect(h.up(), {0: 4.0});
    });

    test('a vertical drag on one cell steps it inside the range', () {
      final g = over('4 4 0 4');
      g.down(5, 9, 1);
      expect(g.moveTo(5, 7), isEmpty, reason: 'under one step');
      expect(g.moveTo(5, 3), {0: 2.0}, reason: 'up one step');
      // A step drag stays on its cell, however far it travels.
      expect(g.moveTo(5, -40), {0: 4.0}, reason: 'clamped to the maximum');
      expect(g.moveTo(5, 40), {0: 0.0}, reason: 'down to the minimum');
      expect(g.up(), isEmpty);
    });

    test('a first move mostly up steps, even when it lands past the cell', () {
      final g = over('4 4 0 4');
      g.down(5, 15, 0);
      expect(g.moveTo(7, 2), {1: 2.0});
    });

    test('leaving the cell first paints the toggled value', () {
      final g = over('4 4 0 4');
      g.down(5, 5, 0);
      expect(g.moveTo(25, 5), {0: 4.0, 4: 4.0, 8: 4.0});
      expect(g.up(), isEmpty);
    });
  });
}
