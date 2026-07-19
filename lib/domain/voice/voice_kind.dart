/// The two kinds of `voice.` a note can address (design
/// `docs/design/racks-and-voices.md` §3, §10 decision 2).
///
/// A voice binds *note → sound → bus*. An [internal] voice instantiates its own
/// engine synth from a `synth.` definition; an [external] voice plays through the
/// open MIDI output port on a fixed channel. Clips and code address a voice by
/// name and never care which kind it is. Serialised by [name].
enum VoiceKind {
  /// Plays an internal engine synth built from a `synth.` definition.
  internal,

  /// Plays external hardware through the MIDI output port on a fixed channel.
  external,
}
