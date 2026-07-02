import 'always_condition.dart';
import 'edge_condition.dart';
import 'transform_node_id.dart';

/// A directed, guarded connection between two graph vertices.
///
/// Notes flow from [fromId] to [toId] whenever [condition] is satisfied by the
/// evaluation context. [fromId] may be [TransformNodeId.source]; [toId] is
/// always a real node. The graph keeps at most one edge per `(fromId, toId)`
/// pair — model alternative guards with a single richer [EdgeCondition]
/// rather than parallel edges.
class TransformEdge {
  const TransformEdge({
    required this.fromId,
    required this.toId,
    this.condition = const AlwaysCondition(),
  });

  final TransformNodeId fromId;
  final TransformNodeId toId;
  final EdgeCondition condition;

  /// Two edges are equal when they connect the same ordered pair *and* carry
  /// the same guard. Pair-level de-duplication is the graph's job, not the
  /// value type's.
  @override
  bool operator ==(Object other) =>
      other is TransformEdge &&
      other.fromId == fromId &&
      other.toId == toId &&
      other.condition == condition;

  @override
  int get hashCode => Object.hash(fromId, toId, condition);
}
