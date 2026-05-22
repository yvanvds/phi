import 'performance_state_id.dart';

/// A directed edge between two [PerformanceState]s.
///
/// Immutable value object. To "move" a transition, remove and add; to
/// change [armed] or [fireOn], replace the instance via [copyWith] —
/// [StateGraph] does this in place when its `toggleArmed` / `fire` /
/// `setArmed` methods are called.
///
/// Equality is on `(sourceId, targetId)` only — two transitions with the
/// same endpoints but different `armed` / `fireOn` are still "the same
/// edge". That keeps duplicate-detection in [StateGraph] a cheap
/// `contains` call and lets the graph look up the current state of an
/// edge by its endpoints alone.
class StateTransition {
  const StateTransition({
    required this.sourceId,
    required this.targetId,
    this.armed = false,
    this.fireOn = 'manual',
  });

  final PerformanceStateId sourceId;
  final PerformanceStateId targetId;

  /// Whether this transition is staged to fire on the next trigger.
  /// Multiple transitions may be armed simultaneously; [StateGraph.fire]
  /// clears every arm in one go.
  final bool armed;

  /// Free-form label rendered in the target node's "armed" capsule
  /// ("manual", "4 bars", "audio > −18", …). The trigger semantics
  /// behind the label arrive with the time-domain / sensor layers; for
  /// now the label is purely cosmetic.
  final String fireOn;

  StateTransition copyWith({bool? armed, String? fireOn}) => StateTransition(
    sourceId: sourceId,
    targetId: targetId,
    armed: armed ?? this.armed,
    fireOn: fireOn ?? this.fireOn,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StateTransition &&
          other.sourceId == sourceId &&
          other.targetId == targetId);

  @override
  int get hashCode => Object.hash(sourceId, targetId);
}
