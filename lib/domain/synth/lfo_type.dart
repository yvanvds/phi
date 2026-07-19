/// The virtual-analog LFO shapes (mirrors the engine's `LfoType`, design
/// `docs/design/racks-and-voices.md` §4).
///
/// A pure-domain enum kept independent of the engine; the gateway maps it onto
/// `package:yse`'s `LfoType`. Serialised by [name].
enum LfoType {
  /// No modulation — the LFO is off.
  none,

  /// Rising sawtooth.
  saw,

  /// Falling sawtooth.
  sawReversed,

  /// Triangle.
  triangle,

  /// Sine.
  sine,

  /// Square.
  square,

  /// Sample-and-hold random.
  random,
}
