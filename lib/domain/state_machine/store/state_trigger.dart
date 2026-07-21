import '../../project/entity_address.dart';

/// What fires a [StateTransitionSpec] — the persisted trigger *data* of design
/// `docs/design/state-graph.md` §5 (issue #240).
///
/// Each transition carries exactly one trigger. Four kinds ship in v1:
///
/// - [ManualTrigger] — today's arm + fire capsule.
/// - [CodeTrigger] — `state.x.fire()` through the `phi` control plane.
/// - [TimedTrigger] — N beats after entering the source state, on a `domain.`
///   clock.
/// - [VariableTrigger] — fires when a runtime variable takes a value.
///
/// This is the payload's *data model only*: the scheduling / firing behaviour
/// (and the editors) land with issue #244. A sealed family (the
/// [NoteCondition] precedent) so a `switch` over kinds is exhaustive; each
/// variant is an immutable value type with a stable JSON form tagged by
/// `kind`.
sealed class StateTrigger {
  const StateTrigger();

  /// Rebuilds a trigger from the map [toJson] produced. Throws a
  /// [FormatException] on a missing/unknown `kind` or a malformed field — a
  /// half-specified trigger fires nothing, so a corrupt file fails loudly.
  factory StateTrigger.fromJson(Map<String, Object?> json) {
    switch (json['kind']) {
      case 'manual':
        return const ManualTrigger();
      case 'code':
        return const CodeTrigger();
      case 'timed':
        final beats = (json['beats'] as num?)?.toDouble();
        final domain = json['domain'] as String?;
        if (beats == null || domain == null) {
          throw const FormatException(
            'A timed trigger needs "beats" and a "domain" address.',
          );
        }
        return TimedTrigger(beats: beats, domain: EntityAddress.parse(domain));
      case 'variable':
        final name = json['name'] as String?;
        final value = json['value'] as String?;
        if (name == null || value == null) {
          throw const FormatException(
            'A variable trigger needs a "name" and a "value".',
          );
        }
        return VariableTrigger(name: name, value: value);
      default:
        throw FormatException('Unknown trigger kind: "${json['kind']}".');
    }
  }

  /// The stable wire tag for this trigger's kind.
  String get kind;

  /// The addresses this trigger points at — a [TimedTrigger]'s `domain.`
  /// clock; empty for the other kinds. Feeds [StateDocument.references].
  Set<EntityAddress> get references => const {};

  /// A copy with any reference to [from] repointed to [to] — the refactor
  /// step a rename/move triggers. The default is the identity (no addresses
  /// to repoint).
  StateTrigger withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      this;

  /// The trigger as its JSON map, tagged with [kind].
  Map<String, Object?> toJson() => {'kind': kind};
}

/// Fires by hand — arm the transition, then tap the capsule (design §5).
final class ManualTrigger extends StateTrigger {
  const ManualTrigger();

  @override
  String get kind => 'manual';

  @override
  bool operator ==(Object other) => other is ManualTrigger;

  @override
  int get hashCode => (ManualTrigger).hashCode;
}

/// Fires from live code — `state.x.fire()` via the `phi` control plane
/// (design §5; the behaviour seam is issue #244).
final class CodeTrigger extends StateTrigger {
  const CodeTrigger();

  @override
  String get kind => 'code';

  @override
  bool operator ==(Object other) => other is CodeTrigger;

  @override
  int get hashCode => (CodeTrigger).hashCode;
}

/// Fires [beats] beats after the source state goes live, counted on the
/// [domain] clock — cancelled when the state is left first (design §5).
final class TimedTrigger extends StateTrigger {
  const TimedTrigger({required this.beats, required this.domain});

  /// How many beats after entry the transition fires. Beats are fractional
  /// throughout the timing layer, so this is a double.
  final double beats;

  /// The `domain.` entity whose clock counts the beats.
  final EntityAddress domain;

  @override
  String get kind => 'timed';

  @override
  Set<EntityAddress> get references => {domain};

  @override
  StateTrigger withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      domain == from ? TimedTrigger(beats: beats, domain: to) : this;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'beats': beats,
    'domain': domain.format(),
  };

  @override
  bool operator ==(Object other) =>
      other is TimedTrigger && other.beats == beats && other.domain == domain;

  @override
  int get hashCode => Object.hash(beats, domain);
}

/// Fires when the runtime variable [name] takes [value] — checked on variable
/// change, not polled (design §5). Values are strings, matching the
/// [RuntimeVariable] value-type decision (issue #78).
final class VariableTrigger extends StateTrigger {
  const VariableTrigger({required this.name, required this.value});

  /// The runtime variable watched.
  final String name;

  /// The value that fires the transition.
  final String value;

  @override
  String get kind => 'variable';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'name': name, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is VariableTrigger && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}
