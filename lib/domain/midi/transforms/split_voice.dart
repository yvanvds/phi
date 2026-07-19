/// One target layer of a [SplittingTransform]: where the copy goes and how
/// it differs from the source note.
///
/// A `SplitVoice()` with all defaults reproduces the source note exactly —
/// include one to keep the original alongside the layers. [voice] `null`
/// means "keep the note's incoming voice" so a split can add an octave
/// without also re-routing.
class SplitVoice {
  const SplitVoice({
    this.voice,
    this.pitchOffset = 0,
    this.velocityScale = 1.0,
  });

  /// Target `voice.` address for this layer, or `null` to keep the source voice.
  final String? voice;

  /// Semitones added to the source pitch — `12` layers an octave up.
  final int pitchOffset;

  /// Multiplier on the source velocity, e.g. `0.5` for a quieter double.
  final double velocityScale;
}
