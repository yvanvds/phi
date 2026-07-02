import '../../state_machine/performance_state_id.dart';
import 'edge_condition.dart';
import 'graph_eval_context.dart';

/// Opens the edge only while a specific state-machine state is live.
///
/// This is what makes the mockup's `branch · state.break` real: an edge
/// carrying `StateMatchCondition(breakStateId)` routes notes down the break
/// branch exactly when the [StateGraph]'s `activeStateId` is that state, and
/// is closed otherwise.
class StateMatchCondition extends EdgeCondition {
  const StateMatchCondition(this.stateId);

  /// The state that must be live for this edge to open.
  final PerformanceStateId stateId;

  @override
  bool isSatisfiedBy(GraphEvalContext context) =>
      context.activeStateId == stateId;

  @override
  String get label => 'state · ${stateId.value}';

  @override
  bool operator ==(Object other) =>
      other is StateMatchCondition && other.stateId == stateId;

  @override
  int get hashCode => stateId.hashCode;
}
