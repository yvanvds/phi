import '../../time_domains/time_domain.dart';
import '../../time_domains/time_domain_registry.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';

/// Binds a clip's transport to a named [TimeDomain]'s clock (issues #61/#102).
///
/// A subscription is a **clock choice, not a note rewrite**. In the engine-clock
/// world (see `docs/timing-architecture.md` §4) the clip stays in
/// domain-beats and the *transport's* clock decides how fast those beats
/// advance: subscribing to `drum @ 124` runs the bound clock at 124 BPM, so the
/// phrase plays at the domain's tempo without any note's start or duration
/// changing. Locking to a faster domain makes the phrase end sooner in
/// wall-clock time (the clock ticks faster); a slower domain stretches it — but
/// the beat numbers the notes carry are untouched.
///
/// This inverts the original transform, which baked `referenceTempo /
/// domainTempo` into every note's timing at evaluation time. Rescaling the
/// notes was wrong by construction once tempo became a played control signal:
/// every live tempo nudge would invalidate the pushed event list and force a
/// re-evaluate + re-push, smuggling the rescheduling problem back in through the
/// data. Keeping tempo in the clock makes tempo changes free — the engine
/// integrates the new rate and the clip bends immediately, no re-push.
///
/// So [apply] is the **identity**: a subscription contributes no change to the
/// note stream. What it contributes is [boundTempo] — the tempo the player runs
/// the transport's clock at while the chip is active — read by
/// `EngineMidiController`, not by the note pipeline. Pitch, velocity, channel,
/// and timing all pass through unchanged.
///
/// The domain is resolved by [domainName] through a [TimeDomainRegistry] — see
/// [DomainSubscriptionTransform.resolve]. Resolution happens once, at
/// construction, so [apply] stays pure and registry-free. When the name doesn't
/// resolve, [boundTempo] is `null`: there is nothing to bind against, so the
/// player falls back to the session tempo.
class DomainSubscriptionTransform extends MidiTransform {
  const DomainSubscriptionTransform({
    required this.domainName,
    required this.label,
    this.domain,
    this.active = true,
  });

  /// Resolves [domainName] against [registry] and binds the result. The
  /// domain may be absent from the registry — [boundTempo] is then `null`
  /// until a domain by that name exists.
  factory DomainSubscriptionTransform.resolve({
    required TimeDomainRegistry registry,
    required String domainName,
    required String label,
    bool active = true,
  }) => DomainSubscriptionTransform(
    domainName: domainName,
    label: label,
    domain: registry.resolve(domainName),
    active: active,
  );

  /// The subscribed domain's name — also the registry key it resolves through.
  final String domainName;

  /// The resolved domain to bind the clock to, or `null` when [domainName]
  /// didn't resolve. A `null` domain leaves [boundTempo] `null`.
  final TimeDomain? domain;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.time;

  /// The tempo (BPM) the player should run the bound clock at while this
  /// subscription is active, or `null` when it resolves no domain (nothing to
  /// bind — the clip plays at the session tempo). Read by the engine player to
  /// pick the transport's clock tempo; the note pipeline never sees it.
  double? get boundTempo => domain?.tempo;

  /// Identity: a subscription binds a clock, it does not rewrite note times.
  /// Tempo lives in the clock ([boundTempo]), not in the note data.
  @override
  List<MidiNote> apply(List<MidiNote> input) => input;

  @override
  DomainSubscriptionTransform copyWith({bool? active, String? label}) =>
      DomainSubscriptionTransform(
        domainName: domainName,
        label: label ?? this.label,
        domain: domain,
        active: active ?? this.active,
      );
}
