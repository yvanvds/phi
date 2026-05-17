/// Snapshot of engine-level telemetry sampled from the audio thread.
///
/// Emitted periodically by `PhiEngine.telemetry` so the bottom status strip
/// and (Phase 1) the Mix surface can show live values without each widget
/// polling the engine itself.
class EngineTelemetry {
  const EngineTelemetry({
    required this.cpuLoad,
    required this.missedCallbacks,
  });

  /// Audio thread CPU load as a fraction of the callback budget, `[0, 1]`.
  final double cpuLoad;

  /// Cumulative count of audio callbacks that missed their deadline.
  final int missedCallbacks;

  static const EngineTelemetry zero =
      EngineTelemetry(cpuLoad: 0, missedCallbacks: 0);
}
