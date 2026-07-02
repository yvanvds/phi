import 'graph_eval_context.dart';

/// The guard on a [TransformEdge] — decides whether notes flow down that
/// branch for a given [GraphEvalContext].
///
/// Vision §3.7: "Which transformations apply is context-dependent. A clip in
/// state A is transformed one way; in state B, differently." The condition is
/// where that context-dependence lives. An unconditional branch uses
/// [AlwaysCondition]; the two concrete guards wired today are
/// [StateMatchCondition] (live state-machine state) and
/// [RuntimeVariableCondition] (named runtime variable).
///
/// Implementations are immutable and pure — [isSatisfiedBy] must not mutate
/// the context or the graph, so evaluation is repeatable.
abstract class EdgeCondition {
  const EdgeCondition();

  /// Whether the edge this guards is open under [context].
  bool isSatisfiedBy(GraphEvalContext context);

  /// Short human label the node-and-cable UI paints on the cable.
  String get label;
}
