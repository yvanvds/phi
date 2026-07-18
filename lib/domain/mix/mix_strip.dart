/// The persisted state of a mix channel — a `mix.` registry entity's payload
/// (design `docs/design/project-registry.md` §2, entity-kinds table).
///
/// A strip carries what must survive a save/reload: the channel's display
/// [name] (which may contain spaces and capitals the entity address cannot — the
/// address is a slug of it), its voice-swatch [voice], and — since issue #136 —
/// the live mixing state the performer dials in: user-set [volume], [muted], and
/// [soloed]. That live state was engine-only performance state through the v1
/// migration (#124); persisting it is the mix epic's job, fed by
/// **gesture-coalesced** fader/mute/solo commands so the journal does not bloat
/// with per-tick writes (design §6).
///
/// A plain, immutable value type. It (de)serialises to a JSON map so the strip is
/// journal-friendly (a `mix.` entity is created and edited through the ordinary
/// registry command layer, whose `toJson` must be JSON-encodable) and compares by
/// value so a round-trip is easy to assert.
class MixStrip {
  /// Builds a strip. [voice] is the 1..6 swatch index; it is not range-checked
  /// here (the engine assigns it). [volume] is the user-set fader value in
  /// `[0, 1]`; [muted]/[soloed] default to off — a fresh channel is at unity,
  /// unmuted, unsoloed.
  const MixStrip({
    required this.name,
    required this.voice,
    this.volume = 1.0,
    this.muted = false,
    this.soloed = false,
  });

  /// Reads a strip from a decoded payload map, tolerating missing keys by
  /// falling back to sensible defaults so a hand-edited or older file (a v1
  /// `mix.` payload carried only `name` + `voice`) still loads at unity volume,
  /// unmuted and unsoloed.
  factory MixStrip.fromJson(Map<String, Object?> json) => MixStrip(
    name: json['name'] as String? ?? 'channel',
    voice: (json['voice'] as num?)?.toInt() ?? 1,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    muted: json['muted'] as bool? ?? false,
    soloed: json['soloed'] as bool? ?? false,
  );

  /// The channel's display name — what the strip header shows. May contain
  /// characters the entity address (a slug of this) cannot.
  final String name;

  /// The voice-swatch index in `[1, 6]`.
  final int voice;

  /// The user-set fader volume in `[0.0, 1.0]` — what the performer dialled in,
  /// independent of the *effective* gateway volume mute/solo may collapse it to.
  final double volume;

  /// Whether the channel is muted.
  final bool muted;

  /// Whether the channel is soloed.
  final bool soloed;

  MixStrip copyWith({
    String? name,
    int? voice,
    double? volume,
    bool? muted,
    bool? soloed,
  }) => MixStrip(
    name: name ?? this.name,
    voice: voice ?? this.voice,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    soloed: soloed ?? this.soloed,
  );

  /// The strip as the JSON map stored in the `mix.` entity's payload.
  Map<String, Object?> toJson() => {
    'name': name,
    'voice': voice,
    'volume': volume,
    'muted': muted,
    'soloed': soloed,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MixStrip &&
          other.name == name &&
          other.voice == voice &&
          other.volume == volume &&
          other.muted == muted &&
          other.soloed == soloed;

  @override
  int get hashCode => Object.hash(name, voice, volume, muted, soloed);

  @override
  String toString() =>
      'MixStrip($name, voice: $voice, volume: $volume, '
      'muted: $muted, soloed: $soloed)';
}
