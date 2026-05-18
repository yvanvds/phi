/// Snapshot of engine-level telemetry sampled from the audio thread.
///
/// Emitted periodically by `PhiEngine.telemetry` so the bottom status strip
/// and the Mix surface can show live values without each widget polling
/// the engine itself.
class EngineTelemetry {
  const EngineTelemetry({
    required this.cpuLoad,
    required this.missedCallbacks,
    required this.masterPeak,
    required this.sampleRate,
    required this.bufferSize,
    required this.latencyMs,
  });

  /// Audio thread CPU load as a fraction of the callback budget, `[0, 1]`.
  final double cpuLoad;

  /// Cumulative count of audio callbacks that missed their deadline.
  final int missedCallbacks;

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
    missedCallbacks: 0,
    masterPeak: 0,
    sampleRate: 0,
    bufferSize: 0,
    latencyMs: 0,
  );
}
