/// Whether a port carries audio-rate or control-rate data.
///
/// Audio-rate ports correspond to YSE's `~`-prefixed object inlets/outlets
/// (DSP buffers). Control-rate ports carry typed messages (ints, floats,
/// strings, lists) at much lower rates. Cables can only connect ports of
/// the same kind — the patcher controller rejects mismatched connections.
enum PatchPortKind {
  /// DSP signal — drawn as a solid voiced cable.
  audio,

  /// Control messages — drawn as a dashed voiced cable.
  control,
}
