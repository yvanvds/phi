import '../../project/entity_address.dart';
import 'edge_condition.dart';
import 'graph_eval_context.dart';

/// Opens the edge only while a specific `state.` entity is live.
///
/// This is what makes the mockup's `branch · state.break` real: an edge
/// carrying `StateMatchCondition(state.break's address)` routes notes down the
/// break branch exactly when the live state is that entity, and is closed
/// otherwise.
///
/// Since issue #240 the guard names the state by **entity address** rather
/// than by a canvas-local id — the uniform `state.` name used in live code and
/// completion — so a persisted guard re-binds by name across sessions and
/// rides the ordinary rename-refactor (wired registry-wide by issue #241).
class StateMatchCondition extends EdgeCondition {
  const StateMatchCondition(this.state);

  /// The `state.` entity that must be live for this edge to open.
  final EntityAddress state;

  @override
  bool isSatisfiedBy(GraphEvalContext context) => context.activeState == state;

  @override
  String get label => 'state · ${state.name}';

  @override
  bool operator ==(Object other) =>
      other is StateMatchCondition && other.state == state;

  @override
  int get hashCode => state.hashCode;
}
