/// Abstract port over the `package:yse` library.
///
/// `PhiEngine` depends on this interface, not on `package:yse` directly, so
/// tests can swap in a fake gateway and the production code is the only
/// place the real FFI surface is touched. See `real_yse_gateway.dart` for
/// the production implementation.
abstract interface class YseGateway {
  /// Initialise the audio engine and open the default device.
  void init();

  /// Shut the engine down.
  void close();

  /// Begin the periodic engine-update timer at the given [interval].
  void startUpdateTimer([Duration interval]);

  /// CPU load of the audio thread as a fraction of the callback budget.
  double get cpuLoad;

  /// Number of audio callbacks that failed to complete on time.
  int get missedCallbacks;

  /// Toggle the engine's built-in audio test signal.
  set audioTest(bool on);

  /// Master-channel volume, in `[0.0, 1.0]`.
  double get masterVolume;
  set masterVolume(double value);

  /// Peak amplitude on the master channel, measured post-volume — the level
  /// listeners actually hear. Linear, `[0.0, 1.0+]`; values above 1.0 mean
  /// clipping. Sampled once per telemetry tick.
  double get masterPeak;

  /// Sample rate of the currently open audio device, in Hz. `0` when no
  /// device is open.
  double get activeSampleRate;

  /// Frames-per-callback of the currently open audio device. `0` when no
  /// device is open.
  int get activeBufferSize;

  /// Output latency of the currently open audio device, in samples. `0` when
  /// no device is open. Convert to ms with
  /// `(activeOutputLatency / activeSampleRate) * 1000`.
  int get activeOutputLatency;

  /// Broadcast stream that emits a tick on every MIDI input message the
  /// engine receives. UI uses this to flash an activity indicator; the
  /// payload is intentionally empty (a single in/out distinction is not
  /// yet exposed).
  Stream<void> get midiActivity;
}
