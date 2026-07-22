import '../project/entity_address.dart';

/// A directed edge between two `state.` entities, as the canvas renders and
/// interacts with it (issue #241).
///
/// Immutable value object the registry-backed `StateMachineController`
/// derives from the source state's persisted `StateTransitionSpec` list: the
/// [source] / [target] addresses come from the payload, [fireOn] from the
/// spec's label or trigger kind, and [armed] from the controller's transient
/// arm set — arming is performance state and never persists.
///
/// Equality is on `(source, target)` only — two transitions with the same
/// endpoints but different `armed` / `fireOn` are still "the same edge". That
/// keeps duplicate-detection a cheap `contains` call and lets the controller
/// key its arm set by endpoints alone, which is what lets a rename remap an
/// arm in place (rename mid-arm keeps the arm).
class StateTransition {
  const StateTransition({
    required this.source,
    required this.target,
    this.armed = false,
    this.fireOn = 'manual',
  });

  /// The `state.` entity whose payload carries this transition.
  final EntityAddress source;

  /// The `state.` entity this transition fires toward.
  final EntityAddress target;

  /// Whether this transition is staged to fire on the next trigger.
  /// Multiple transitions may be armed simultaneously; a fire clears every
  /// arm in one go.
  final bool armed;

  /// Label rendered in the target node's "armed" capsule — the spec's label
  /// when set, its trigger kind otherwise ("manual", "timed", …).
  final String fireOn;

  StateTransition copyWith({bool? armed, String? fireOn}) => StateTransition(
    source: source,
    target: target,
    armed: armed ?? this.armed,
    fireOn: fireOn ?? this.fireOn,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StateTransition &&
          other.source == source &&
          other.target == target);

  @override
  int get hashCode => Object.hash(source, target);

  @override
  String toString() =>
      'StateTransition($source → $target'
      '${armed ? ', armed' : ''})';
}
