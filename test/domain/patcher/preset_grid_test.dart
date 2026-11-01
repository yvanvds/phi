import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/preset_grid.dart';

void main() {
  test('a small bank is one row; the default 32 is four rows of eight', () {
    expect((PresetGrid.columnsFor(1), PresetGrid.rowsFor(1)), (1, 1));
    expect((PresetGrid.columnsFor(5), PresetGrid.rowsFor(5)), (5, 1));
    expect((PresetGrid.columnsFor(8), PresetGrid.rowsFor(8)), (8, 1));
    expect((PresetGrid.columnsFor(32), PresetGrid.rowsFor(32)), (8, 4));
    expect((PresetGrid.columnsFor(64), PresetGrid.rowsFor(64)), (8, 8));
  });

  test('a large bank squares up instead of growing tall', () {
    expect((PresetGrid.columnsFor(100), PresetGrid.rowsFor(100)), (10, 10));
    expect((PresetGrid.columnsFor(1024), PresetGrid.rowsFor(1024)), (32, 32));
    expect((PresetGrid.columnsFor(65), PresetGrid.rowsFor(65)), (9, 8));
  });

  test('slots run row by row from the top left', () {
    final grid = PresetGrid(slots: 32, width: 160, height: 80);
    expect(grid.cellWidth, 20);
    expect(grid.cellHeight, 20);
    expect(grid.slotAt(1, 1), 0);
    expect(grid.slotAt(25, 1), 1);
    expect(grid.slotAt(1, 25), 8);
    expect(grid.slotAt(159, 79), 31);
    expect(grid.originOf(9), (20.0, 20.0));
  });

  test('off the grid, or in the unused tail of the last row, is no slot', () {
    final grid = PresetGrid(slots: 10, width: 80, height: 20);
    expect(grid.slotAt(-1, 5), isNull);
    expect(grid.slotAt(80, 5), isNull);
    expect(grid.slotAt(5, 20), isNull);
    expect(grid.slotAt(15, 15), 9, reason: 'the last slot, row 2');
    expect(grid.slotAt(25, 15), isNull, reason: 'past slot 9 in row 2');
    expect(PresetGrid(slots: 4, width: 0, height: 10).slotAt(0, 0), isNull);
  });
}
