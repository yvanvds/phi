import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/matrixctrl_args.dart';

void main() {
  test('defaults to an 8 x 8 on/off grid', () {
    final grid = MatrixctrlArgs.parse('');
    expect(grid.columns, 8);
    expect(grid.rows, 8);
    expect(grid.cellCount, 64);
    expect(grid.range.low, 0);
    expect(grid.range.high, 1);
    expect(grid.stepped, isFalse);
  });

  test('reads columns, rows and an ordered range, skipping words', () {
    final grid = MatrixctrlArgs.parse('16 x 4 4 0');
    expect(grid.columns, 16);
    expect(grid.rows, 4);
    expect(grid.range.low, 0);
    expect(grid.range.high, 4);
    expect(grid.stepped, isTrue);
  });

  test('truncates and clamps each axis to 1-256', () {
    final grid = MatrixctrlArgs.parse('3.9 999');
    expect(grid.columns, 3);
    expect(grid.rows, 256);
    expect(MatrixctrlArgs.parse('0 -4').columns, 1);
    expect(MatrixctrlArgs.parse('0 -4').rows, 1);
  });

  test('flattens column-major', () {
    final grid = MatrixctrlArgs.parse('3 2');
    expect(grid.indexOf(0, 1), 1);
    expect(grid.indexOf(2, 1), 5);
    expect(grid.columnOf(5), 2);
    expect(grid.rowOf(5), 1);
  });
}
