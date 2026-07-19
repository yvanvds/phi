/// The four built-in synth definition kinds (design
/// `docs/design/racks-and-voices.md` §4).
///
/// A `synth.` entity is a *recipe*: its kind selects which payload shape it
/// carries and, later, which engine voice pool the gateway materialises from it
/// (`addSineVoices` / `addVaVoices` / `addFmVoices` / `addSamplerVoices`). The
/// kind is persisted as its [name] in the payload so a definition round-trips
/// without the registry needing to know what a synth is.
enum SynthKind {
  /// A bank of built-in sine voices — the zero-config starter (§4).
  sine,

  /// A virtual-analog + wavetable voice with the full panel (§4).
  va,

  /// A DX7-class 6-operator FM voice built from a sysex bank patch (§4).
  fm,

  /// An SFZ / single-sample sampler voice (§4).
  sampler,
}
