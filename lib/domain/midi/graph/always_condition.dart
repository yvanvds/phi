import 'edge_condition.dart';
import 'graph_eval_context.dart';

/// An unconditional edge — always open, whatever the context.
///
/// This is the default guard on every [TransformEdge], so a graph built with
/// no explicit conditions behaves like the old linear chain: every stage
/// feeds the next.
class AlwaysCondition extends EdgeCondition {
  const AlwaysCondition();

  @override
  bool isSatisfiedBy(GraphEvalContext context) => true;

  @override
  String get label => 'always';

  @override
  bool operator ==(Object other) => other is AlwaysCondition;

  @override
  int get hashCode => (AlwaysCondition).hashCode;
}
