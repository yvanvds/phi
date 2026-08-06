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
  ///
  /// This is also what enumerates the hardware: [audioDevices] is empty until an
  /// `init()` has run (issue #403), so every boot path goes through here.
  void init();

  /// Initialise the engine **without** opening any audio device — headless
  /// rendering and benchmarks.
  ///
  /// **Not a boot path.** An offline session sees **no devices at all**:
  /// [audioDevices] returns an empty list, and the engine refuses to open one
  /// (measured against libyse 2.4.0 — issue #403, dart-yse #51). A later [init]
  /// does not repair it either; the engine ignores a second init until [close].
  void initOffline();

  /// Shut the engine down.
  void close();

  /// The libYSE library version string (e.g. `2.0.1`) — a read-only
  /// diagnostics fact (design §6). Available without a device open.
  String get engineVersion;

  /// The directory the engine library was loaded from, as configured through
  /// the `YSE_DLL_PATH` environment variable — the resolved path shown in the
  /// diagnostics section (design §6). `null` when the variable is unset (the
  /// library then resolves from its bundled/package location).
  String? get libraryPath;

  /// The audio devices the engine can currently see, as pure FFI-free
  /// [AudioDeviceDescriptor]s (design §4) — the list the settings window builds
  /// its output-device dropdown from. Empty until [init] has run — the engine
  /// enumerates as part of opening a device, never on its own, so an
  /// [initOffline] session sees nothing (issue #403).
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
  /// "Refuses" includes the engine's *silent* refusals: it reports a failed open
  /// as a log line rather than a status (dart-yse #52), so an implementation
  /// must confirm a device actually came up before returning normally.
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

  /// Configure engine auto-reconnect (design §4): when [on], the engine re-opens
  /// a device that disappears after [delayMs] ms. Enabled at boot (1 s) and not
  /// exposed as a setting in v1. Safe to call after [init] / [initOffline].
  void setAutoReconnect({required bool on, int delayMs});

  /// Begin the periodic engine-update timer at the given [interval].
  void startUpdateTimer([Duration interval]);

  /// CPU load of the audio thread as a fraction of the callback budget.
  double get cpuLoad;

  /// The engine's **device-stall gauge**: how many *consecutive* engine control
  /// ticks (the [startUpdateTimer] period) saw no audio callback at all.
  ///
  /// Despite the engine spelling it `missedCallbacks`, this is neither
  /// cumulative nor a count of callbacks that missed their deadline — it resets
  /// to `0` on the next control tick that sees a callback, and it is what the
  /// engine's own auto-reconnect watches. At a control tick faster than the
  /// device's callback period a *healthy* device reads `1` here routinely, so
  /// never surface it raw: interpret it with `AudioStallTracker` (issue #350).
  int get deviceStallTicks;

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

  /// Create a new YSE channel and return an opaque integer id. Subsequent
  /// per-channel calls take the same id.
  ///
  /// [parentId] chooses the channel's parent in the mix tree; `null` (the
  /// default) parents to the master channel. Pass another channel's id to nest
  /// this one under it — a child's audio flows through its parent, so the tree
  /// is rooted at master (design `docs/design/mix.md` §3). An unknown
  /// [parentId] falls back to master rather than failing.
  int createChannel(String name, {int? parentId});

  /// Destroy a channel previously returned by [createChannel] (or
  /// [createReturnChannel]). No-op for an unknown id (already destroyed, or
  /// never existed).
  void destroyChannel(int channelId);

  /// Re-parent [channelId] under [parentId], or under master when [parentId] is
  /// `null` — the regroup-as-`moveTo` operation (design §8). All attached
  /// sounds and subchannels follow. No-op for an unknown [channelId]; an
  /// unknown [parentId] resolves to master.
  void moveChannel(int channelId, [int? parentId]);

  /// Create a **return bus** — an aux bus outside the mix tree (design §4) —
  /// and return its opaque id. Other channels route scaled copies of their
  /// signal into it with [setSend]; its output folds into master after the
  /// source tree. A return may itself send onward into another return.
  ///
  /// [sendSlots] fixes how many onward sends this return can drive; it is set
  /// once at creation and never resized. The default of four matches an
  /// ordinary channel; the engine sync raises it when a payload wants more
  /// (design §10 decision 4, `createWithSends` semantics).
  int createReturnChannel(String name, {int sendSlots = 4});

  /// Volume of a non-master channel in `[0.0, 1.0]`.
  double channelVolume(int channelId);
  void setChannelVolume(int channelId, double value);

  /// Post-volume peak amplitude of a non-master channel — linear `[0.0, 1.0+]`.
  /// Sampled once per telemetry tick. Mirrors [masterPeak] for user channels.
  double channelPeak(int channelId);

  /// Wire send [slot] of [channelId] to the return [returnId] at [level].
  ///
  /// Sends are post-fader by default (they follow the channel's volume); pass
  /// [preFader] `true` for a cue-style send independent of the fader. The
  /// engine rejects and logs an illegal wiring — a target that is not a return,
  /// a self-send, a return → return edge that would close a cycle, or an
  /// out-of-range slot — as a no-op rather than an error (design §4).
  void setSend(
    int channelId,
    int slot,
    int returnId,
    double level,
    bool preFader,
  );

  /// Set the level of send [slot] on [channelId], ramped and click-free — safe
  /// to write every control tick (design §4). No-op for an unset slot.
  void setSendLevel(int channelId, int slot, double level);

  /// Detach send [slot] on [channelId], disconnecting it from its return bus.
  void clearSend(int channelId, int slot);

  /// Number of speaker outputs [channelId] feeds — index the per-output peak
  /// reads with `[0, channelOutputCount)`. `0` for an unknown id.
  int channelOutputCount(int channelId);

  /// Post-fader peak on a single [output] of [channelId] — linear `[0.0, 1.0+]`.
  /// Out-of-range outputs read `0`.
  double channelPeakOutput(int channelId, int output);

  /// Pre-fader peak on a single [output] of [channelId] — linear `[0.0, 1.0+]`,
  /// measured before the channel volume (design §6; exposed but no v1 UI).
  /// Out-of-range outputs read `0`.
  double channelPeakPreOutput(int channelId, int output);

  /// Number of speaker outputs the master channel feeds — the master strip
  /// renders one meter bar per output (design §6).
  int get masterOutputCount;

  /// Post-fader peak on a single master [output] — linear `[0.0, 1.0+]`.
  /// Out-of-range outputs read `0`.
  double masterPeakOutput(int output);
}
