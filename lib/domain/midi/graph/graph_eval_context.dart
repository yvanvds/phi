import '../../state_machine/performance_state_id.dart';

/// The runtime facts an [EdgeCondition] consults while a
/// [MidiTransformGraph] is being evaluated.
///
/// It bundles the two context sources vision §3.7 names — the live
/// state-machine state and named runtime variables — behind one immutable
/// value so `evaluate` can be called with a single argument and conditions
/// stay ignorant of *where* the facts come from.
///
/// The default [GraphEvalContext.empty] has no live state and no variables,
/// so only unconditional edges are taken — that is the "simple linear case"
/// the graph must keep usable.
class GraphEvalContext {
  const GraphEvalContext({this.activeStateId, this.variables = const {}});

  /// No live state, no variables — only [AlwaysCondition] edges fire.
  const GraphEvalContext.empty() : activeStateId = null, variables = const {};

  /// The state-machine state currently "live", mirrored from
  /// [StateGraph.activeStateId]. `null` when the performance is between
  /// states or the graph is evaluated in isolation (tests, preview).
  final PerformanceStateId? activeStateId;

  /// Named runtime variables the performance exposes. Values are compared by
  /// `==`, so callers should use stable, hashable value types.
  final Map<String, Object?> variables;

  /// The value of [name], or `null` if unset. A convenience so conditions
  /// don't reach into [variables] directly.
  Object? variable(String name) => variables[name];
}
