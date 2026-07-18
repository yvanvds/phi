import '../../domain/project/app_settings/speaker_layout.dart';
import 'audio_device_descriptor.dart';
import 'audio_device_exception.dart';
import 'audio_device_state.dart';

/// Abstract port over the `package:yse` library.
///
/// `PhiEngine` depends on this interface, not on `package:yse` directly, so
/// tests can swap in a fake gateway and the production code is the only
/// place the real FFI surface is touched. See `real_yse_gateway.dart` for
/// the production implementation.
abstract interface class YseGateway {
  /// Initialise the audio engine and open the default device.
  void init();

  /// Initialise the engine **without** opening any audio device — the boot path
  /// (design `docs/design/settings-and-devices.md` §5) taken when a stored
  /// device must be resolved and opened explicitly. Enumerate with
  /// [audioDevices] and open one with [openAudioDevice].
  void initOffline();

  /// Shut the engine down.
  void close();

  /// The audio devices the engine can currently see, as pure FFI-free
  /// [AudioDeviceDescriptor]s (design §4) — the list the settings window builds
  /// its output-device dropdown from. Available after [init] / [initOffline].
  List<AudioDeviceDescriptor> audioDevices();

  /// Open an audio device, or live-swap to it if one is already open
  /// (`closeCurrentDevice` + `openDevice`, design §5 — a brief dropout is
  /// accepted). Passing a null [descriptor] opens the platform-default device.
  /// [rate] / [buffer] override the device's own defaults when non-null;
  /// [layout] chooses the speaker layout.
  ///
  /// Throws [AudioDeviceException] when the descriptor resolves to no visible
  /// device or the engine refuses to open it — the caller reverts to the
  /// previous working device and shows a notice (design §5). The stored
  /// preference is the caller's concern, never dropped by a failed open.
  void openAudioDevice(
    AudioDeviceDescriptor? descriptor, {
    double? rate,
    int? buffer,
    SpeakerLayout layout = SpeakerLayout.auto,
  });

  /// The live state of the open device — active sample rate, buffer size, and
  /// output latency (design §4). Reads the device, not the stored settings; the
  /// two can legitimately differ. [AudioDeviceState.none] when none is open.
  AudioDeviceState activeAudioState();

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

  /// Create a new YSE channel parented to the master channel and return an
  /// opaque integer id. Subsequent per-channel calls take the same id.
  int createChannel(String name);

  /// Destroy a channel previously returned by [createChannel]. No-op for an
  /// unknown id (already destroyed, or never existed).
  void destroyChannel(int channelId);

  /// Volume of a non-master channel in `[0.0, 1.0]`.
  double channelVolume(int channelId);
  void setChannelVolume(int channelId, double value);

  /// Post-volume peak amplitude of a non-master channel — linear `[0.0, 1.0+]`.
  /// Sampled once per telemetry tick. Mirrors [masterPeak] for user channels.
  double channelPeak(int channelId);
}
