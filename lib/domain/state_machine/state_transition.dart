import 'performance_state_id.dart';

/// A directed edge between two [PerformanceState]s.
///
/// Immutable for now — to "move" a transition, remove and add. Equality
/// is on `(sourceId, targetId)` so duplicate-detection in [StateGraph]
/// is a cheap `contains` call. Arming and fire conditions land in #10b.
class StateTransition {
  const StateTransition({required this.sourceId, required this.targetId});

  final PerformanceStateId sourceId;
  final PerformanceStateId targetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StateTransition &&
          other.sourceId == sourceId &&
          other.targetId == targetId);

  @override
  int get hashCode => Object.hash(sourceId, targetId);
}
