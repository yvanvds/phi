/// A four-stage attack / decay / sustain / release envelope — the shape both
/// the VA amp and filter envelopes take (design `docs/design/racks-and-voices.md`
/// §4).
///
/// A plain, immutable value type: [attack], [decay] and [release] are times in
/// seconds; [sustain] is a level in `[0, 1]`. It (de)serialises to a JSON map and
/// compares by value so a synth payload round-trips cleanly.
class AdsrEnvelope {
  /// Builds an envelope. Defaults are a fast, gentle shape: a short attack, a
  /// moderate decay to a high sustain, a short release.
  const AdsrEnvelope({
    this.attack = 0.01,
    this.decay = 0.1,
    this.sustain = 0.8,
    this.release = 0.2,
  });

  /// Reads an envelope from a decoded map, defaulting any missing stage.
  factory AdsrEnvelope.fromJson(Map<String, Object?> json) => AdsrEnvelope(
    attack: (json['attack'] as num?)?.toDouble() ?? 0.01,
    decay: (json['decay'] as num?)?.toDouble() ?? 0.1,
    sustain: (json['sustain'] as num?)?.toDouble() ?? 0.8,
    release: (json['release'] as num?)?.toDouble() ?? 0.2,
  );

  /// Attack time in seconds.
  final double attack;

  /// Decay time in seconds.
  final double decay;

  /// Sustain level in `[0.0, 1.0]`.
  final double sustain;

  /// Release time in seconds.
  final double release;

  AdsrEnvelope copyWith({
    double? attack,
    double? decay,
    double? sustain,
    double? release,
  }) => AdsrEnvelope(
    attack: attack ?? this.attack,
    decay: decay ?? this.decay,
    sustain: sustain ?? this.sustain,
    release: release ?? this.release,
  );

  /// The envelope as its JSON map. Keys are emitted in a stable order so an
  /// unchanged payload re-encodes byte-identically.
  Map<String, Object?> toJson() => {
    'attack': attack,
    'decay': decay,
    'sustain': sustain,
    'release': release,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdsrEnvelope &&
          other.attack == attack &&
          other.decay == decay &&
          other.sustain == sustain &&
          other.release == release;

  @override
  int get hashCode => Object.hash(attack, decay, sustain, release);

  @override
  String toString() =>
      'AdsrEnvelope(attack: $attack, decay: $decay, sustain: $sustain, '
      'release: $release)';
}
