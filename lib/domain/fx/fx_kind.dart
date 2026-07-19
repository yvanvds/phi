/// The insert-effect kinds a `fx.` entity can be (design
/// `docs/design/racks-and-voices.md` §2, §5) — one per engine `DspObject`
/// factory.
///
/// A pure-domain enum; the gateway maps each onto its `package:yse` factory
/// (`DspObject.lowpass`, `DspObject.granulator`, …) when it materialises the
/// insert chain. Serialised by [name].
enum FxKind {
  /// Resonant low-pass filter (`DspObject.lowpass`).
  lowpass,

  /// Resonant high-pass filter (`DspObject.highpass`).
  highpass,

  /// Band-pass filter (`DspObject.bandpass`).
  bandpass,

  /// Sweeping filter (`DspObject.sweep`).
  sweep,

  /// Clean feedback delay (`DspObject.basicDelay`).
  basicDelay,

  /// Low-pass-in-loop delay (`DspObject.lowpassDelay`).
  lowpassDelay,

  /// High-pass-in-loop delay (`DspObject.highpassDelay`).
  highpassDelay,

  /// Phaser (`DspObject.phaser`).
  phaser,

  /// Ring modulator (`DspObject.ringModulator`).
  ringModulator,

  /// Difference / side-chain subtractor (`DspObject.difference`).
  difference,

  /// Granular processor (`DspObject.granulator`).
  granulator,

  /// Dynamics compressor (the engine's `Compressor`).
  compressor,

  /// A patcher graph used as an insert (`DspObject.patcherInsert`). The kind
  /// exists from day one so nothing re-plumbs when the patcher epic lands its
  /// registry entities (§5); its params/target wiring arrive with that epic.
  patcherInsert,
}
