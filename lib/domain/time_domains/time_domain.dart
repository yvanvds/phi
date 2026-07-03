/// A named tempo reference a clip can lock against.
///
/// The minimal seed of the time-domains layer (issue #60): just a [name]
/// (e.g. `drum`) and a [tempo] in beats-per-minute. A clip's
/// `DomainSubscriptionTransform` (the #32 follow-up) resolves a domain by
/// name through a [TimeDomainRegistry] and tempo-locks to it.
///
/// Immutable, pure Dart — no Flutter imports (domain-layer rule), no engine
/// wiring. Per-domain transport, the toolbar tempo control, and the engine
/// bridge are all explicitly out of scope here; this is the value object a
/// subscription binds to and nothing more.
class TimeDomain {
  const TimeDomain({required this.name, required this.tempo})
    : assert(tempo > 0, 'tempo must be a positive BPM');

  /// Human-facing identifier, also the registry key (e.g. `drum`, `pad`).
  final String name;

  /// Tempo in beats-per-minute. Always positive.
  final double tempo;

  TimeDomain copyWith({String? name, double? tempo}) =>
      TimeDomain(name: name ?? this.name, tempo: tempo ?? this.tempo);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeDomain && other.name == name && other.tempo == tempo;

  @override
  int get hashCode => Object.hash(name, tempo);

  @override
  String toString() => 'TimeDomain($name @ ${tempo}bpm)';
}
