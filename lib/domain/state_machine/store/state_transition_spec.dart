import '../../project/entity_address.dart';
import 'state_trigger.dart';

/// One outbound transition in a `state.` entity's payload — `{to, trigger,
/// label}` (design `docs/design/state-graph.md` §3, issue #240).
///
/// Transitions live in the **source** state's payload as an ordered list; the
/// target is an entity address, so rename-refactor rewrites it and
/// delete-impact on a state lists its inbound transitions. An immutable value
/// type with a stable JSON form.
class StateTransitionSpec {
  const StateTransitionSpec({
    required this.to,
    this.trigger = const ManualTrigger(),
    this.label,
  });

  /// Rebuilds a spec from the map [toJson] produced. Throws a
  /// [FormatException] on a missing/malformed `to` address or trigger.
  factory StateTransitionSpec.fromJson(Map<String, Object?> json) {
    final to = json['to'] as String?;
    if (to == null) {
      throw const FormatException('A transition needs a "to" address.');
    }
    final trigger = json['trigger'];
    return StateTransitionSpec(
      to: EntityAddress.parse(to),
      trigger: trigger is Map
          ? StateTrigger.fromJson(trigger.cast<String, Object?>())
          : const ManualTrigger(),
      label: json['label'] as String?,
    );
  }

  /// The target `state.` entity.
  final EntityAddress to;

  /// What fires this transition (data only until issue #244).
  final StateTrigger trigger;

  /// Optional free-form label the canvas badges the transition with.
  final String? label;

  /// The addresses this transition points at — its target plus whatever the
  /// trigger references (a timed trigger's `domain.` clock).
  Set<EntityAddress> get references => {to, ...trigger.references};

  /// A copy with any reference to [from] repointed to [to] — the refactor
  /// step a rename/move of the target (or the trigger's domain) applies.
  StateTransitionSpec withReferenceUpdated(
    EntityAddress from,
    EntityAddress to,
  ) {
    final repointedTrigger = trigger.withReferenceUpdated(from, to);
    if (this.to != from && identical(repointedTrigger, trigger)) return this;
    return StateTransitionSpec(
      to: this.to == from ? to : this.to,
      trigger: repointedTrigger,
      label: label,
    );
  }

  /// The transition as its JSON map. Keys are in a stable order; the label is
  /// omitted when unset.
  Map<String, Object?> toJson() => {
    'to': to.format(),
    'trigger': trigger.toJson(),
    if (label != null) 'label': label,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateTransitionSpec &&
          other.to == to &&
          other.trigger == trigger &&
          other.label == label;

  @override
  int get hashCode => Object.hash(to, trigger, label);

  @override
  String toString() =>
      'StateTransitionSpec(to: $to, trigger: ${trigger.kind}, label: $label)';
}
