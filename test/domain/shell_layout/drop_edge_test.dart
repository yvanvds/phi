import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/shell_layout/drop_edge.dart';
import 'package:phi/domain/shell_layout/split_axis.dart';

void main() {
  group('DropEdge', () {
    test('vertical edges split along a row, horizontal along a column', () {
      expect(DropEdge.left.axis, SplitAxis.row);
      expect(DropEdge.right.axis, SplitAxis.row);
      expect(DropEdge.top.axis, SplitAxis.column);
      expect(DropEdge.bottom.axis, SplitAxis.column);
    });

    test('left and top place the new pane before the target', () {
      expect(DropEdge.left.placesBefore, isTrue);
      expect(DropEdge.top.placesBefore, isTrue);
      expect(DropEdge.right.placesBefore, isFalse);
      expect(DropEdge.bottom.placesBefore, isFalse);
    });
  });
}
