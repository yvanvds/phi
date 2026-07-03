import '../../time_domains/time_domain.dart';
import '../../time_domains/time_domain_registry.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Tempo-locks a clip to a named [TimeDomain] (issue #61).
///
/// A clip's beats are authored against a [referenceTempo] (the session
/// tempo the notes were written at). Subscribing to a domain re-expresses
/// those beats so the phrase *sounds* at the domain's tempo when the
/// downstream player still reads beats at the reference rate: every note's
/// start and duration is scaled by `referenceTempo / domainTempo`. Locking
/// to a faster domain (`domainTempo > referenceTempo`) compresses the beats
/// so the phrase plays faster; a slower domain stretches them. Pitch,
/// velocity, and channel are untouched — a subscription only rescales
/// *when* notes play.
///
/// The domain is resolved by [domainName] through a [TimeDomainRegistry] —
/// see [DomainSubscriptionTransform.resolve]. Resolution happens once, at
/// construction, so [apply] stays pure and registry-free. When the name
/// doesn't resolve (or the domain is already at the reference tempo) the
/// transform is the identity: there is nothing to lock against, so the beats
/// pass through unchanged rather than collapsing to zero.
class DomainSubscriptionTransform extends MidiTransform {
  const DomainSubscriptionTransform({
    required this.domainName,
    required this.referenceTempo,
    required this.label,
    this.domain,
    this.active = true,
  }) : assert(referenceTempo > 0, 'referenceTempo must be a positive BPM');

  /// Resolves [domainName] against [registry] and binds the result. The
  /// domain may be absent from the registry — the transform then behaves as
  /// the identity until a domain by that name exists.
  factory DomainSubscriptionTransform.resolve({
    required TimeDomainRegistry registry,
    required String domainName,
    required double referenceTempo,
    required String label,
    bool active = true,
  }) => DomainSubscriptionTransform(
    domainName: domainName,
    referenceTempo: referenceTempo,
    label: label,
    domain: registry.resolve(domainName),
    active: active,
  );

  /// The subscribed domain's name — also the registry key it resolves through.
  final String domainName;

  /// Tempo (BPM) the clip's beats were authored against. Always positive.
  final double referenceTempo;

  /// The resolved domain to lock against, or `null` when [domainName] didn't
  /// resolve. A `null` domain makes [apply] the identity.
  final TimeDomain? domain;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.time;

  /// The tempo ratio baked into each beat: `referenceTempo / domainTempo`.
  /// `1.0` when unresolved or already at the reference tempo (identity).
  double get scale {
    final d = domain;
    if (d == null) return 1.0;
    return referenceTempo / d.tempo;
  }

  @override
  List<MidiNote> apply(List<MidiNote> input) {
    final s = scale;
    if (s == 1.0) return input;
    return input
        .map((n) => n.copyWith(start: n.start * s, duration: n.duration * s))
        .toList(growable: false);
  }

  @override
  DomainSubscriptionTransform copyWith({bool? active, String? label}) =>
      DomainSubscriptionTransform(
        domainName: domainName,
        referenceTempo: referenceTempo,
        label: label ?? this.label,
        domain: domain,
        active: active ?? this.active,
      );
}
