/// The persisted identity of a mix channel — a `mix.` registry entity's payload
/// (design `docs/design/project-registry.md` §2, entity-kinds table).
///
/// A strip carries only what must survive a save/reload: the channel's display
/// [name] (which may contain spaces and capitals the entity address cannot — the
/// address is a slug of it) and its voice-swatch [voice]. Live mixing state
/// (volume, mute, solo, peak) is *performance* state the engine owns on its
/// `MixerChannel`; persisting it — with gesture-coalesced fader commands — is the
/// mix epic's job, not this migration's ("naming + persistence only").
///
/// A plain, immutable value type. It (de)serialises to a JSON map so the strip is
/// journal-friendly (a `mix.` entity is created through the ordinary registry
/// command layer, whose `toJson` must be JSON-encodable) and compares by value so
/// a round-trip is easy to assert.
class MixStrip {
  /// Builds a strip. [voice] is the 1..6 swatch index; it is not range-checked
  /// here (the engine assigns it).
  const MixStrip({required this.name, required this.voice});

  /// Reads a strip from a decoded payload map, tolerating missing keys by
  /// falling back to sensible defaults so a hand-edited or older file still
  /// loads.
  factory MixStrip.fromJson(Map<String, Object?> json) => MixStrip(
    name: json['name'] as String? ?? 'channel',
    voice: (json['voice'] as num?)?.toInt() ?? 1,
  );

  /// The channel's display name — what the strip header shows. May contain
  /// characters the entity address (a slug of this) cannot.
  final String name;

  /// The voice-swatch index in `[1, 6]`.
  final int voice;

  MixStrip copyWith({String? name, int? voice}) =>
      MixStrip(name: name ?? this.name, voice: voice ?? this.voice);

  /// The strip as the JSON map stored in the `mix.` entity's payload.
  Map<String, Object?> toJson() => {'name': name, 'voice': voice};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MixStrip && other.name == name && other.voice == voice;

  @override
  int get hashCode => Object.hash(name, voice);

  @override
  String toString() => 'MixStrip($name, voice: $voice)';
}
