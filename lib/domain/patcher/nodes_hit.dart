import 'nodes_hit_part.dart';

/// A press on a `.nodes` node (issue #476): which node, and which [part].
class NodesHit {
  const NodesHit(this.index, this.part);

  final int index;
  final NodesHitPart part;

  @override
  bool operator ==(Object other) =>
      other is NodesHit && other.index == index && other.part == part;

  @override
  int get hashCode => Object.hash(index, part);

  @override
  String toString() => 'NodesHit($index, $part)';
}
