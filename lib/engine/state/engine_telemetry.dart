/// Snapshot of engine-level telemetry sampled from the audio thread.
///
/// Emitted periodically by `PhiEngine.telemetry` so the bottom status strip
/// and the Mix surface can show live values without each widget polling
/// the engine itself.
class EngineTelemetry {
  const EngineTelemetry({
    required this.cpuLoad,
    required this.audioStalls,
    required this.deviceStallTicks,
    required this.peakStallTicks,
    required this.masterPeak,
    required this.sampleRate,
    required this.bufferSize,
    required this.latencyMs,
  });

  /// Audio thread CPU load as a fraction of the callback budget, `[0, 1]`.
  final double cpuLoad;

  /// Cumulative number of **audio stall events** since the engine started — one
  /// per run of control ticks long enough to mean the device really went silent
  /// (see `AudioStallTracker`). This is what the `DROPS` chip shows; it latches
  /// on the leading edge, so a stall that lasts counts once (issue #350).
  final int audioStalls;

  /// The engine's raw device-stall gauge at this tick: how many *consecutive*
  /// engine control ticks saw no audio callback at all. Resets to `0` on the
  /// next tick that sees one, so it is neither cumulative nor a count of
  /// callbacks that missed a deadline. A healthy device reads `1` here
  /// routinely — diagnostics detail, never a user-facing drop count.
  final int deviceStallTicks;

  /// The highest [deviceStallTicks] seen since the engine started — the "how bad
  /// did it get" companion to [audioStalls], carried in the diagnostics bundle.
  final int peakStallTicks;

  /// Post-volume peak amplitude on the master channel, linear `[0, 1+]`.
  /// Values above 1.0 indicate clipping.
  final double masterPeak;

  /// Active device sample rate in Hz. `0` when no device is open.
  final double sampleRate;

  /// Active device frames-per-callback. `0` when no device is open.
  final int bufferSize;

  /// Output latency of the open device in milliseconds. `0` when no device
  /// is open.
  final double latencyMs;

  static const EngineTelemetry zero = EngineTelemetry(
    cpuLoad: 0,
    audioStalls: 0,
    deviceStallTicks: 0,
    peakStallTicks: 0,
    masterPeak: 0,
    sampleRate: 0,
    bufferSize: 0,
    latencyMs: 0,
  );
}
