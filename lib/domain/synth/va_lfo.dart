import 'lfo_type.dart';

/// The virtual-analog LFO section (design
/// `docs/design/racks-and-voices.md` §4).
///
/// Carries the LFO [type], its [rate] in Hz, and its three modulation depths:
/// [toPitch] in semitones, [toCutoff] in octaves, and [toWavetable] as a `[0, 1]`
/// morph amount. A plain, immutable value type that (de)serialises to a JSON map.
class VaLfo {
  /// Builds an LFO. Defaults to off ([LfoType.none]) at a slow rate with no
  /// modulation routed.
  const VaLfo({
    this.type = LfoType.none,
    this.rate = 1.0,
    this.toPitch = 0.0,
    this.toCutoff = 0.0,
    this.toWavetable = 0.0,
  });

  /// Reads an LFO from a decoded map, defaulting missing keys and any unknown
  /// [type] name back to [LfoType.none].
  factory VaLfo.fromJson(Map<String, Object?> json) => VaLfo(
    type: _typeByName(json['type'] as String?),
    rate: (json['rate'] as num?)?.toDouble() ?? 1.0,
    toPitch: (json['toPitch'] as num?)?.toDouble() ?? 0.0,
    toCutoff: (json['toCutoff'] as num?)?.toDouble() ?? 0.0,
    toWavetable: (json['toWavetable'] as num?)?.toDouble() ?? 0.0,
  );

  /// The LFO shape.
  final LfoType type;

  /// LFO rate in Hz.
  final double rate;

  /// Depth routed to pitch, in semitones.
  final double toPitch;

  /// Depth routed to filter cutoff, in octaves.
  final double toCutoff;

  /// Depth routed to wavetable position, in `[0.0, 1.0]`.
  final double toWavetable;

  VaLfo copyWith({
    LfoType? type,
    double? rate,
    double? toPitch,
    double? toCutoff,
    double? toWavetable,
  }) => VaLfo(
    type: type ?? this.type,
    rate: rate ?? this.rate,
    toPitch: toPitch ?? this.toPitch,
    toCutoff: toCutoff ?? this.toCutoff,
    toWavetable: toWavetable ?? this.toWavetable,
  );

  /// The LFO as its JSON map, keys in a stable order.
  Map<String, Object?> toJson() => {
    'type': type.name,
    'rate': rate,
    'toPitch': toPitch,
    'toCutoff': toCutoff,
    'toWavetable': toWavetable,
  };

  static LfoType _typeByName(String? name) => LfoType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => LfoType.none,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaLfo &&
          other.type == type &&
          other.rate == rate &&
          other.toPitch == toPitch &&
          other.toCutoff == toCutoff &&
          other.toWavetable == toWavetable;

  @override
  int get hashCode => Object.hash(type, rate, toPitch, toCutoff, toWavetable);

  @override
  String toString() =>
      'VaLfo(type: ${type.name}, rate: $rate, toPitch: $toPitch, '
      'toCutoff: $toCutoff, toWavetable: $toWavetable)';
}
