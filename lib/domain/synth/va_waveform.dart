/// The virtual-analog oscillator waveforms (mirrors the engine's `VaWaveform`,
/// design `docs/design/racks-and-voices.md` §4).
///
/// A pure-domain enum: the domain owns its own vocabulary and never imports the
/// engine, so the gateway maps these onto `package:yse`'s `VaWaveform` when it
/// materialises a VA voice. Serialised by [name].
enum VaWaveform {
  /// Band-limited sawtooth.
  saw,

  /// Band-limited pulse with variable width (PWM).
  pulse,

  /// Band-limited triangle.
  triangle,

  /// Sine.
  sine,

  /// White noise.
  noise,

  /// Morph across the wavetable bank.
  wavetable,
}
