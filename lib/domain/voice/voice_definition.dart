import '../project/entity_address.dart';
import '../project/reference_source.dart';
import 'voice_kind.dart';

/// The payload of a `voice.` registry entity — the keystone that binds what a
/// note needs (design `docs/design/racks-and-voices.md` §3).
///
/// A voice carries its [kind], its [output] mix bus, and its [color] (a design
/// token name — the domain stays token-agnostic, the design layer resolves it to
/// a swatch). What it plays depends on the kind:
///
/// - **[VoiceKind.internal]** points at a `synth.` definition ([synth]); the
///   engine instantiates its own synth from that recipe. Its engine channel is
///   assigned separately by the project's channel-allocation table, *not* stored
///   here — re-pointing the synth swaps the sound behind a stable identity (§3).
/// - **[VoiceKind.external]** carries a MIDI [channel] in `[1, 16]` and plays the
///   open output port instead of an internal synth ([synth] is `null`).
///
/// **A [ReferenceSource].** A voice points at its `synth.` definition and its
/// `mix.` bus by address, so those edges feed the registry's back-reference index
/// (delete-impact and rename-refactor, design §4). [withReferenceUpdated] repoints
/// whichever of [synth]/[output] a rename or move touches.
///
/// A plain, immutable value type: it (de)serialises to a JSON map (addresses in
/// dotted string form so the payload stays journal-friendly) and compares by
/// value so a round-trip is easy to assert.
class VoiceDefinition implements ReferenceSource {
  /// Builds an internal voice playing [synth] out of [output].
  const VoiceDefinition.internal({
    required EntityAddress this.synth,
    required this.output,
    this.color = defaultColor,
  }) : kind = VoiceKind.internal,
       channel = null;

  /// Builds an external voice on MIDI [channel] (`1..16`) out of [output].
  const VoiceDefinition.external({
    required int this.channel,
    required this.output,
    this.color = defaultColor,
  }) : kind = VoiceKind.external,
       synth = null;

  const VoiceDefinition._({
    required this.kind,
    required this.synth,
    required this.channel,
    required this.output,
    required this.color,
  });

  /// Reads a voice from a decoded map, dispatching on its `kind`. Throws a
  /// [FormatException] on a missing/unknown kind, a missing `output`, or a
  /// missing `synth` (internal) / `channel` (external) — a half-specified voice
  /// binds nothing.
  factory VoiceDefinition.fromJson(Map<String, Object?> json) {
    final kind = _kindByName(json['kind'] as String?);
    final output = EntityAddress.parse(_require(json, 'output'));
    final color = json['color'] as String? ?? defaultColor;
    switch (kind) {
      case VoiceKind.internal:
        return VoiceDefinition.internal(
          synth: EntityAddress.parse(_require(json, 'synth')),
          output: output,
          color: color,
        );
      case VoiceKind.external:
        final channel = (json['channel'] as num?)?.toInt();
        if (channel == null) {
          throw const FormatException(
            'An external voice needs a MIDI "channel".',
          );
        }
        return VoiceDefinition.external(
          channel: channel,
          output: output,
          color: color,
        );
    }
  }

  /// The default voice colour token — the first quick-pick swatch.
  static const String defaultColor = 'voice1';

  /// Whether this voice plays an internal synth or external hardware.
  final VoiceKind kind;

  /// The `synth.` definition this voice instantiates, or `null` for an external
  /// voice.
  final EntityAddress? synth;

  /// The MIDI channel (`1..16`) an external voice plays, or `null` for an
  /// internal voice (whose engine channel comes from the allocation table).
  final int? channel;

  /// The `mix.` bus this voice's output routes to.
  final EntityAddress output;

  /// The voice colour — a design token name (a quick-pick `voice1..voice6` or any
  /// full-palette token). The domain stores the token opaquely (§10 decision 5).
  final String color;

  /// The addresses this voice points at — its `synth.` definition (internal) and
  /// its `mix.` bus — feeding the back-reference index (design §4).
  @override
  Set<EntityAddress> get references => {?synth, output};

  /// A copy with any reference to [from] repointed to [to] — the refactor a
  /// synth's or bus's rename/move triggers. Applying the inverse restores the
  /// original, so undo round-trips.
  @override
  VoiceDefinition withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      VoiceDefinition._(
        kind: kind,
        synth: synth == from ? to : synth,
        channel: channel,
        output: output == from ? to : output,
        color: color,
      );

  /// A copy with the [output] bus, [color], and (kind-appropriate) [synth] or
  /// [channel] replaced. Keeps the voice's kind — re-pointing an internal voice
  /// at a synth or an external voice at a channel.
  VoiceDefinition copyWith({
    EntityAddress? synth,
    int? channel,
    EntityAddress? output,
    String? color,
  }) => VoiceDefinition._(
    kind: kind,
    synth: kind == VoiceKind.internal ? (synth ?? this.synth) : null,
    channel: kind == VoiceKind.external ? (channel ?? this.channel) : null,
    output: output ?? this.output,
    color: color ?? this.color,
  );

  /// The voice as its JSON map. Only the kind-relevant binding (`synth` or
  /// `channel`) is emitted; addresses are written in dotted form so the payload
  /// stays JSON-encodable. Keys are in a stable order.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (synth != null) 'synth': synth!.format(),
    if (channel != null) 'channel': channel,
    'output': output.format(),
    'color': color,
  };

  static VoiceKind _kindByName(String? name) {
    for (final k in VoiceKind.values) {
      if (k.name == name) return k;
    }
    throw FormatException('Unknown voice kind: "$name".');
  }

  static String _require(Map<String, Object?> json, String key) {
    final value = json[key] as String?;
    if (value == null) {
      throw FormatException('A voice needs a "$key" address.');
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceDefinition &&
          other.kind == kind &&
          other.synth == synth &&
          other.channel == channel &&
          other.output == output &&
          other.color == color;

  @override
  int get hashCode => Object.hash(kind, synth, channel, output, color);

  @override
  String toString() =>
      'VoiceDefinition(kind: ${kind.name}, synth: $synth, channel: $channel, '
      'output: $output, color: $color)';
}
