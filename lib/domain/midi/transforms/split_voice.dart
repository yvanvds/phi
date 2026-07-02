/// One target layer of a [SplittingTransform]: where the copy goes and how
/// it differs from the source note.
///
/// A `SplitVoice()` with all defaults reproduces the source note exactly —
/// include one to keep the original alongside the layers. [channel] `null`
/// means "keep the note's incoming channel" so a split can add an octave
/// without also re-routing.
class SplitVoice {
  const SplitVoice({
    this.channel,
    this.pitchOffset = 0,
    this.velocityScale = 1.0,
  });

  /// Target channel for this layer, or `null` to keep the source channel.
  final int? channel;

  /// Semitones added to the source pitch — `12` layers an octave up.
  final int pitchOffset;

  /// Multiplier on the source velocity, e.g. `0.5` for a quieter double.
  final double velocityScale;
}
