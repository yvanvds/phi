import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/field_node.dart';

void main() {
  test('reads one <x> <y> <radius> cell, as the engine spells it', () {
    expect(FieldNode.parse('0.25 0.75 0.5'), const FieldNode(0.25, 0.75, 0.5));
    expect(FieldNode.parse('0. 0. 1.'), const FieldNode(0, 0, 1));
  });

  test('a cell without three numbers is no node', () {
    expect(FieldNode.parse(''), isNull);
    expect(FieldNode.parse('0.5 0.5'), isNull);
    expect(FieldNode.parse('a b c'), isNull);
  });
}
