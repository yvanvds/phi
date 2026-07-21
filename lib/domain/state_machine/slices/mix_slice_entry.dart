import '../../project/entity_address.dart';

/// One entry of a state's **mix** slice — the captured volume/mute of a
/// chosen `mix.` bus (design `docs/design/state-graph.md` §4, issue #240).
class MixSliceEntry {
  const MixSliceEntry({
    required this.bus,
    required this.volume,
    this.muted = false,
  });

  /// Rebuilds an entry from the map [toJson] produced. Throws a
  /// [FormatException] on a missing/malformed `bus` address or volume.
  factory MixSliceEntry.fromJson(Map<String, Object?> json) {
    final bus = json['bus'] as String?;
    final volume = (json['volume'] as num?)?.toDouble();
    if (bus == null || volume == null) {
      throw const FormatException(
        'A mix slice entry needs a "bus" address and a "volume".',
      );
    }
    return MixSliceEntry(
      bus: EntityAddress.parse(bus),
      volume: volume,
      muted: json['muted'] as bool? ?? false,
    );
  }

  /// The `mix.` bus (entity strip or group bus) the levels apply to.
  final EntityAddress bus;

  /// The captured fader volume, normalised `0..1`.
  final double volume;

  /// The captured mute flag.
  final bool muted;

  /// A copy with the bus address repointed when it equals [from].
  MixSliceEntry withReferenceUpdated(EntityAddress from, EntityAddress to) =>
      bus == from ? MixSliceEntry(bus: to, volume: volume, muted: muted) : this;

  /// The entry as its JSON map.
  Map<String, Object?> toJson() => {
    'bus': bus.format(),
    'volume': volume,
    'muted': muted,
  };

  @override
  bool operator ==(Object other) =>
      other is MixSliceEntry &&
      other.bus == bus &&
      other.volume == volume &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(bus, volume, muted);
}
