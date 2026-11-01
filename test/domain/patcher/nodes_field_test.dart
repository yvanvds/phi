import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/field_node.dart';
import 'package:phi/domain/patcher/nodes_field.dart';

void main() {
  const pair = [FieldNode(0, 0, 1), FieldNode(1, 0, 1)];

  test('the distance from the cursor to each node', () {
    expect(NodesField.distances(pair, 0.25, 0), [0.25, 0.75]);
  });

  test('weights are the proximities normalised to sum to 1', () {
    final w = NodesField.weights(pair, 0.25, 0);
    expect(w[0], closeTo(0.75, 1e-12));
    expect(w[1], closeTo(0.25, 1e-12));
  });

  test('inside one node only, it takes the whole weight', () {
    const apart = [FieldNode(0.25, 0.25, 0.2), FieldNode(0.75, 0.75, 0.2)];
    expect(NodesField.weights(apart, 0.3, 0.3), [1, 0]);
  });

  test('outside every node the weights are all 0, not a fallback', () {
    const apart = [FieldNode(0.25, 0.25, 0.2), FieldNode(0.75, 0.75, 0.2)];
    expect(NodesField.weights(apart, 0.5, 0.5), [0, 0]);
  });

  test('a node of radius 0, negative or NaN covers nothing', () {
    const muted = [
      FieldNode(0.5, 0.5, 0),
      FieldNode(0.5, 0.5, -1),
      FieldNode(0.5, 0.5, double.nan),
      FieldNode(0.5, 0.5, 1),
    ];
    expect(NodesField.weights(muted, 0.5, 0.5), [0, 0, 0, 1]);
  });

  test('the neutral start: four unit nodes at the origin share equally', () {
    final start = List.filled(4, const FieldNode(0, 0, 1));
    expect(NodesField.weights(start, 0, 0), [0.25, 0.25, 0.25, 0.25]);
  });
}
