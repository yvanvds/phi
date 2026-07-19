import 'va_waveform.dart';

/// One oscillator of a virtual-analog voice (design
/// `docs/design/racks-and-voices.md` §4).
///
/// A VA voice layers several of these — [VaSynth.oscillators]. Each carries its
/// [wave], its [detune] in semitones, its mix [level] in `[0, 1]`, and (for the
/// pulse wave) its [pulseWidth] in `[0, 1]`. A plain, immutable value type that
/// (de)serialises to a JSON map.
class VaOscillator {
  /// Builds an oscillator. Defaults to a unity-level sawtooth at concert pitch
  /// with a square 50% pulse width.
  const VaOscillator({
    this.wave = VaWaveform.saw,
    this.detune = 0.0,
    this.level = 1.0,
    this.pulseWidth = 0.5,
  });

  /// Reads an oscillator from a decoded map, defaulting missing keys and any
  /// unknown [wave] name back to a sawtooth.
  factory VaOscillator.fromJson(Map<String, Object?> json) => VaOscillator(
    wave: _waveByName(json['wave'] as String?),
    detune: (json['detune'] as num?)?.toDouble() ?? 0.0,
    level: (json['level'] as num?)?.toDouble() ?? 1.0,
    pulseWidth: (json['pulseWidth'] as num?)?.toDouble() ?? 0.5,
  );

  /// The oscillator waveform.
  final VaWaveform wave;

  /// Detune in semitones, relative to the played note.
  final double detune;

  /// Mix level in `[0.0, 1.0]`.
  final double level;

  /// Pulse width in `[0.0, 1.0]`, used when [wave] is [VaWaveform.pulse].
  final double pulseWidth;

  VaOscillator copyWith({
    VaWaveform? wave,
    double? detune,
    double? level,
    double? pulseWidth,
  }) => VaOscillator(
    wave: wave ?? this.wave,
    detune: detune ?? this.detune,
    level: level ?? this.level,
    pulseWidth: pulseWidth ?? this.pulseWidth,
  );

  /// The oscillator as its JSON map, keys in a stable order.
  Map<String, Object?> toJson() => {
    'wave': wave.name,
    'detune': detune,
    'level': level,
    'pulseWidth': pulseWidth,
  };

  static VaWaveform _waveByName(String? name) => VaWaveform.values.firstWhere(
    (w) => w.name == name,
    orElse: () => VaWaveform.saw,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaOscillator &&
          other.wave == wave &&
          other.detune == detune &&
          other.level == level &&
          other.pulseWidth == pulseWidth;

  @override
  int get hashCode => Object.hash(wave, detune, level, pulseWidth);

  @override
  String toString() =>
      'VaOscillator(wave: ${wave.name}, detune: $detune, level: $level, '
      'pulseWidth: $pulseWidth)';
}
