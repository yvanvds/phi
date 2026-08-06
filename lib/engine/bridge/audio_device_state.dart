/// The live state of whichever audio device is currently open (design
/// `docs/design/settings-and-devices.md` §4) — what the diagnostics section
/// reads back, **not** the stored settings (the two can legitimately differ, so
/// the read-back line shows the truth).
///
/// A pure, FFI-free snapshot returned by [YseGateway.activeAudioState]. All
/// fields are zero when no device is open (the [none] instance) — pre-init,
/// after close, or throughout an `initOffline` session, which never opens one
/// (it cannot: it enumerates no devices at all — issue #403).
class AudioDeviceState {
  /// Builds a state snapshot. Defaults describe "no device open".
  const AudioDeviceState({
    this.sampleRate = 0,
    this.bufferSize = 0,
    this.outputLatency = 0,
  });

  /// Sample rate of the open device, in Hz. `0` when none is open.
  final double sampleRate;

  /// Frames-per-callback of the open device. `0` when none is open.
  final int bufferSize;

  /// Output latency of the open device, in samples. `0` when none is open.
  final int outputLatency;

  /// The output latency expressed in milliseconds, `0` when no device is open
  /// (or the sample rate is unknown). The read-back line shows this.
  double get outputLatencyMs =>
      sampleRate > 0 ? (outputLatency / sampleRate) * 1000 : 0.0;

  /// The "no device open" snapshot — every field zero.
  static const AudioDeviceState none = AudioDeviceState();

  @override
  bool operator ==(Object other) =>
      other is AudioDeviceState &&
      other.sampleRate == sampleRate &&
      other.bufferSize == bufferSize &&
      other.outputLatency == outputLatency;

  @override
  int get hashCode => Object.hash(sampleRate, bufferSize, outputLatency);

  @override
  String toString() =>
      'AudioDeviceState(sampleRate: $sampleRate, bufferSize: $bufferSize, '
      'outputLatency: $outputLatency)';
}
