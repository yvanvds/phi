import 'adsr_envelope.dart';
import 'synth_definition.dart';
import 'synth_kind.dart';
import 'va_filter.dart';
import 'va_lfo.dart';
import 'va_oscillator.dart';

/// A `synth.` definition of kind [SynthKind.va] — the virtual-analog + wavetable
/// voice with the **full panel** (design `docs/design/racks-and-voices.md` §4).
///
/// Carries the whole VA recipe: a stack of [oscillators], the global
/// [wavetablePosition], the [filter] section, the [ampEnvelope] plus its
/// [ampVelAmount], the [filterEnvelope], the [lfo] section, the output [gain],
/// and the [voiceCount]. A plain, immutable value type — every field survives a
/// JSON round-trip.
class VaSynth extends SynthDefinition {
  /// Builds a VA definition. Defaults give a single sawtooth oscillator through a
  /// wide-open filter with a gentle amp envelope and the LFO off — a usable
  /// starting patch.
  const VaSynth({
    this.oscillators = const [VaOscillator()],
    this.wavetablePosition = 0.0,
    this.filter = const VaFilter(),
    this.ampEnvelope = const AdsrEnvelope(),
    this.ampVelAmount = 0.0,
    this.filterEnvelope = const AdsrEnvelope(),
    this.lfo = const VaLfo(),
    this.gain = 1.0,
    this.voiceCount = 8,
  });

  /// Reads a VA definition from a decoded map, defaulting any missing section.
  /// An absent or empty oscillator list falls back to a single default
  /// oscillator so a VA voice always has at least one.
  factory VaSynth.fromJson(Map<String, Object?> json) {
    final oscillators = [
      for (final osc in (json['oscillators'] as List<Object?>? ?? const []))
        VaOscillator.fromJson((osc as Map).cast<String, Object?>()),
    ];
    return VaSynth(
      oscillators: oscillators.isEmpty ? const [VaOscillator()] : oscillators,
      wavetablePosition: (json['wavetablePosition'] as num?)?.toDouble() ?? 0.0,
      filter: json['filter'] == null
          ? const VaFilter()
          : VaFilter.fromJson((json['filter'] as Map).cast<String, Object?>()),
      ampEnvelope: json['ampEnvelope'] == null
          ? const AdsrEnvelope()
          : AdsrEnvelope.fromJson(
              (json['ampEnvelope'] as Map).cast<String, Object?>(),
            ),
      ampVelAmount: (json['ampVelAmount'] as num?)?.toDouble() ?? 0.0,
      filterEnvelope: json['filterEnvelope'] == null
          ? const AdsrEnvelope()
          : AdsrEnvelope.fromJson(
              (json['filterEnvelope'] as Map).cast<String, Object?>(),
            ),
      lfo: json['lfo'] == null
          ? const VaLfo()
          : VaLfo.fromJson((json['lfo'] as Map).cast<String, Object?>()),
      gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
      voiceCount: (json['voiceCount'] as num?)?.toInt() ?? 8,
    );
  }

  /// The oscillator stack — always at least one.
  final List<VaOscillator> oscillators;

  /// Wavetable morph position in `[0.0, 1.0]`.
  final double wavetablePosition;

  /// The resonant filter section.
  final VaFilter filter;

  /// The amplitude envelope.
  final AdsrEnvelope ampEnvelope;

  /// Velocity-to-amplitude depth in `[0.0, 1.0]`.
  final double ampVelAmount;

  /// The filter envelope (its depth lives on [VaFilter.envAmount]).
  final AdsrEnvelope filterEnvelope;

  /// The LFO section.
  final VaLfo lfo;

  /// Output gain in `[0.0, 1.0]`.
  final double gain;

  @override
  SynthKind get kind => SynthKind.va;

  @override
  final int voiceCount;

  VaSynth copyWith({
    List<VaOscillator>? oscillators,
    double? wavetablePosition,
    VaFilter? filter,
    AdsrEnvelope? ampEnvelope,
    double? ampVelAmount,
    AdsrEnvelope? filterEnvelope,
    VaLfo? lfo,
    double? gain,
    int? voiceCount,
  }) => VaSynth(
    oscillators: oscillators ?? this.oscillators,
    wavetablePosition: wavetablePosition ?? this.wavetablePosition,
    filter: filter ?? this.filter,
    ampEnvelope: ampEnvelope ?? this.ampEnvelope,
    ampVelAmount: ampVelAmount ?? this.ampVelAmount,
    filterEnvelope: filterEnvelope ?? this.filterEnvelope,
    lfo: lfo ?? this.lfo,
    gain: gain ?? this.gain,
    voiceCount: voiceCount ?? this.voiceCount,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'oscillators': [for (final osc in oscillators) osc.toJson()],
    'wavetablePosition': wavetablePosition,
    'filter': filter.toJson(),
    'ampEnvelope': ampEnvelope.toJson(),
    'ampVelAmount': ampVelAmount,
    'filterEnvelope': filterEnvelope.toJson(),
    'lfo': lfo.toJson(),
    'gain': gain,
    'voiceCount': voiceCount,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaSynth &&
          _oscillatorsEqual(other.oscillators, oscillators) &&
          other.wavetablePosition == wavetablePosition &&
          other.filter == filter &&
          other.ampEnvelope == ampEnvelope &&
          other.ampVelAmount == ampVelAmount &&
          other.filterEnvelope == filterEnvelope &&
          other.lfo == lfo &&
          other.gain == gain &&
          other.voiceCount == voiceCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(oscillators),
    wavetablePosition,
    filter,
    ampEnvelope,
    ampVelAmount,
    filterEnvelope,
    lfo,
    gain,
    voiceCount,
  );

  @override
  String toString() =>
      'VaSynth(oscillators: $oscillators, wavetablePosition: '
      '$wavetablePosition, filter: $filter, ampEnvelope: $ampEnvelope, '
      'ampVelAmount: $ampVelAmount, filterEnvelope: $filterEnvelope, lfo: $lfo, '
      'gain: $gain, voiceCount: $voiceCount)';

  /// Element-wise oscillator-list equality — `List.==` is identity, and the
  /// domain stays Flutter-free so it cannot borrow `foundation`'s `listEquals`.
  static bool _oscillatorsEqual(List<VaOscillator> a, List<VaOscillator> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
