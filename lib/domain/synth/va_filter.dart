/// The virtual-analog filter section (design
/// `docs/design/racks-and-voices.md` §4).
///
/// Carries the resonant low-pass panel: [cutoff] in Hz, [resonance] in `[0, 1]`,
/// keyboard [keyTracking] in `[0, 1]`, and the filter envelope / velocity
/// modulation depths in octaves ([envAmount], [velAmount]). A plain, immutable
/// value type that (de)serialises to a JSON map.
class VaFilter {
  /// Builds a filter. Defaults to a wide-open cutoff with no resonance, tracking
  /// or modulation.
  const VaFilter({
    this.cutoff = 20000.0,
    this.resonance = 0.0,
    this.keyTracking = 0.0,
    this.envAmount = 0.0,
    this.velAmount = 0.0,
  });

  /// Reads a filter from a decoded map, defaulting any missing key.
  factory VaFilter.fromJson(Map<String, Object?> json) => VaFilter(
    cutoff: (json['cutoff'] as num?)?.toDouble() ?? 20000.0,
    resonance: (json['resonance'] as num?)?.toDouble() ?? 0.0,
    keyTracking: (json['keyTracking'] as num?)?.toDouble() ?? 0.0,
    envAmount: (json['envAmount'] as num?)?.toDouble() ?? 0.0,
    velAmount: (json['velAmount'] as num?)?.toDouble() ?? 0.0,
  );

  /// Cutoff frequency in Hz.
  final double cutoff;

  /// Resonance in `[0.0, 1.0]`.
  final double resonance;

  /// Keyboard tracking amount in `[0.0, 1.0]`.
  final double keyTracking;

  /// Filter-envelope depth in octaves.
  final double envAmount;

  /// Velocity-to-cutoff depth in octaves.
  final double velAmount;

  VaFilter copyWith({
    double? cutoff,
    double? resonance,
    double? keyTracking,
    double? envAmount,
    double? velAmount,
  }) => VaFilter(
    cutoff: cutoff ?? this.cutoff,
    resonance: resonance ?? this.resonance,
    keyTracking: keyTracking ?? this.keyTracking,
    envAmount: envAmount ?? this.envAmount,
    velAmount: velAmount ?? this.velAmount,
  );

  /// The filter as its JSON map, keys in a stable order.
  Map<String, Object?> toJson() => {
    'cutoff': cutoff,
    'resonance': resonance,
    'keyTracking': keyTracking,
    'envAmount': envAmount,
    'velAmount': velAmount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaFilter &&
          other.cutoff == cutoff &&
          other.resonance == resonance &&
          other.keyTracking == keyTracking &&
          other.envAmount == envAmount &&
          other.velAmount == velAmount;

  @override
  int get hashCode =>
      Object.hash(cutoff, resonance, keyTracking, envAmount, velAmount);

  @override
  String toString() =>
      'VaFilter(cutoff: $cutoff, resonance: $resonance, '
      'keyTracking: $keyTracking, envAmount: $envAmount, velAmount: $velAmount)';
}
