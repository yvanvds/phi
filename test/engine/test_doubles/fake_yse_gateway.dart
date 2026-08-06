import 'dart:async';

import 'package:phi/domain/project/app_settings/speaker_layout.dart';
import 'package:phi/engine/bridge/audio_device_descriptor.dart';
import 'package:phi/engine/bridge/audio_device_exception.dart';
import 'package:phi/engine/bridge/audio_device_state.dart';
import 'package:phi/engine/bridge/yse_gateway.dart';

/// In-memory [YseGateway] used in unit and widget tests.
///
/// Records every call against the engine so tests can assert call sequence
/// without touching `package:yse` or its native library. Fabricates audio
/// hardware ([devices]) so the settings window is fully drivable without any —
/// visible only once [init] has *enumerated* it, as the engine does;
/// [init] and [openAudioDevice] reflect what the engine opened into the
/// active-state fields, [close] tears that state back down the way
/// `System::close()` does, and [unopenableDeviceNames] simulates a device that
/// is present but refuses to open (the design §5 fallback path) — which, once
/// the target has resolved, leaves the machine device-less, because the real
/// gateway closes the running device before it attempts the new one.
///
/// **Two lists, not one** (issue #412). [devices] is the *hardware*: what is
/// physically in the machine, which a test reassigns to plug and unplug. What
/// [audioDevices] hands back is a separate, frozen **enumeration cache**, taken
/// once at the first [init] — because that is all libyse has. `System.devices`
/// is a plain accessor over a vector filled by `updateDeviceList()`, whose only
/// call site is `deviceManager::init(true)`; `closeCurrentDevice()`,
/// `System::close()` and a later `init()` all leave it alone, and since
/// `Pa_Terminate()` runs only in the manager's destructor, even a close + init
/// re-reads the device table PortAudio captured at the *first* `Pa_Initialize()`.
/// There is no in-process path to a fresh list, and no exported refresh call
/// (dart-yse #51). So a device unplugged mid-session keeps its cached entry with
/// its old index and only *fails to open*, and a device plugged in mid-session is
/// invisible until the process restarts — which, here, means a new
/// [FakeYseGateway]. A fake whose list shrank and grew let tests recover from
/// hardware the shipped app could never see.
///
/// The rule this double is held to: a call with an *observable state effect* on
/// the real gateway must reproduce that effect here, not merely append to
/// [calls]. A fake that records without transitioning tells consumers a lie
/// that no unit test can catch, because every test is reading the same lie
/// (issues #398, #399).
class FakeYseGateway implements YseGateway {
  final List<String> calls = [];
  bool initialised = false;
  bool audioTestOn = false;

  /// Fabricated libYSE version + resolved library path the diagnostics section
  /// reads back (design §6). Reassign to model other values (or an unset path).
  String engineVersionValue = 'fake-yse 0.0.0';
  String? libraryPathValue = r'C:\fake\yse\bin';
  double cpuLoadValue = 0;

  /// The engine's device-stall gauge: consecutive control ticks with no audio
  /// callback. Drive it to model a healthy device (a transient `1`) or a real
  /// stall (a sustained run) — see `AudioStallTracker`.
  int deviceStallTicksValue = 0;
  double activeSampleRateValue = 0;
  int activeBufferSizeValue = 0;
  int activeOutputLatencyValue = 0;

  final StreamController<void> _midiActivity =
      StreamController<void>.broadcast();

  /// Whether the gateway is currently subscribed to its MIDI inputs, as
  /// `_openMidiInputs()` / `_closeMidiInputs()` model it on the real gateway:
  /// nothing is subscribed before [init] / [initOffline], and [close] cancels
  /// what was.
  bool _midiInputsOpen = false;

  /// Push a synthetic MIDI tick — drives listeners as if a hardware port had
  /// delivered an event. Silent before [init] and after [close], because the
  /// real gateway holds no port subscriptions then: hardware traffic reaches
  /// no listener until the engine is (re-)initialised.
  void emitMidiActivity() {
    if (!_midiInputsOpen) return;
    _midiActivity.add(null);
  }

  @override
  Stream<void> get midiActivity => _midiActivity.stream;

  @override
  void init() {
    calls.add('init');
    // `system::initShared()` early-returns on `Global().active` ("You're trying
    // to initialize more than once!"), so an init that lands on a live engine
    // changes nothing — measured: `initOffline()` then `init()` still reports
    // zero devices. A fake that enumerated here would offer a repair the engine
    // does not have (issue #403).
    if (initialised) return;
    initialised = true;
    _midiInputsOpen = true;
    _resetPerSessionGauges();
    // Enumeration is a side effect of *opening* a device, not of initialising:
    // the engine's device manager only calls `updateDeviceList()` on the
    // `init(true)` path (issue #403). So this is the call that makes hardware
    // visible — see [audioDevices]. It snapshots [devices] and never looks
    // again: a second `init()` re-runs `updateDeviceList()` over PortAudio's
    // original table, which yields the same list (issue #412).
    _enumeratedCache ??= List<AudioDeviceDescriptor>.unmodifiable(_devices);
    // The native `System::init()` brings the platform-default device up with
    // it — only `initOffline()` comes up device-less. Reflect that here, or a
    // fake that booted the default device reads back as "no device open" and
    // every consumer of `activeAudioState()` (the status-bar health monitor,
    // the latency chips) sees a machine whose audio just fell away.
    _openPlatformDefault();
  }

  @override
  void initOffline() {
    calls.add('initOffline');
    if (initialised) return; // same one-init-per-session rule as [init]
    initialised = true;
    _midiInputsOpen = true;
    _resetPerSessionGauges();
    // Deliberately *no* enumeration: an offline session sees no hardware at
    // all (issue #403). Measured against libyse 2.4.0 on Windows —
    // `initOffline()` then `System.devices` is empty, where `init()` reports
    // 19 devices on the same machine. The engine skips `Pa_Initialize()` and
    // `updateDeviceList()` when it is not opening a device, and there is no
    // lazy refresh behind the accessor.
  }

  /// Everything `system::initShared()` blanks once it is past the
  /// "more than once" guard, and *only* what it blanks (issue #402). Measured
  /// against the engine source: the guard returns first, then
  ///
  /// ```cpp
  /// INTERNAL::Global().init();
  /// currentlyMissedCallbacks = 0;
  /// doAutoReconnect = false;
  /// reconnectDelay = 0;
  /// ```
  ///
  /// runs before the device manager comes up, on both the `init()` and the
  /// [initOffline] path. So these are *init-side* resets, not close-side ones:
  /// [close] deliberately leaves them alone, because the native `close()` does
  /// too — a session that ends stalled keeps its stall count until something
  /// starts a new one.
  void _resetPerSessionGauges() {
    // The stall gauge is per-session. `close()` never touches
    // `currentlyMissedCallbacks`; `initShared()` zeroes it, and `update()`
    // clears it again on any tick that saw a callback. A fake that carried the
    // previous session's stall run into a fresh engine would hand
    // `AudioStallTracker` a device that boots already unhealthy.
    deviceStallTicksValue = 0;
    // Auto-reconnect is engine state, not a preference: `initShared()` resets
    // `doAutoReconnect` / `reconnectDelay` to off, so a re-init silently
    // disarms whatever the last session configured. `AudioDeviceCoordinator`
    // re-asserts it right after `init()` (deliberately off — issue #410), and
    // that call is only *load-bearing* because the engine forgets.
    autoReconnectOn = null;
    autoReconnectDelayMs = null;
    // The master channel's *impl* is destroyed by `System::close()`
    // (`CHANNEL::Manager().destroy()` clears `implementations`) and re-created
    // by `init()` through `master().createGlobal()`. The fresh impl is born at
    // unity — `implementationObject::implementationObject` hard-codes
    // `newVolume(1.f), lastVolume(1.f)` — and nothing replays a VOLUME message,
    // so the gain the engine actually applies is 1.0 again. See
    // [appliedMasterVolume] for why that is *not* the same as what
    // [masterVolume] reports.
    appliedMasterVolume = 1.0;
  }

  /// Brings the platform default (the first entry of [devices]) up in the live
  /// state, as `System::init()` does natively. Leaves [openedDevice] alone —
  /// that records *explicit* [openAudioDevice] calls, which is what the device
  /// rules (design §5) are asserted through. A machine with no audio hardware
  /// (or whose default refuses to open) stays device-less.
  void _openPlatformDefault() {
    final visible = audioDevices();
    if (visible.isEmpty) return;
    final target = visible.first;
    if (!_isPluggedIn(target)) return;
    if (unopenableDeviceNames.contains(target.name)) return;
    _liveDevice = target;
    activeSampleRateValue = target.sampleRates.isNotEmpty
        ? target.sampleRates.first
        : 0;
    activeBufferSizeValue = target.defaultBufferSize;
    activeOutputLatencyValue = target.outputLatency;
  }

  /// Drops the live device state to "nothing is open", as
  /// `DEVICE::managerObject::close()` does natively: the open flag goes false
  /// (so `getActiveSampleRate()` reads 0) and the active buffer / latency are
  /// stored as 0. Shared by [close] and the failed-open path.
  void _closeDeviceState() {
    _liveDevice = null;
    activeSampleRateValue = 0;
    activeBufferSizeValue = 0;
    activeOutputLatencyValue = 0;
  }

  @override
  void close() {
    calls.add('close');
    initialised = false;
    // `close()` is not a recording — it tears the engine down. The real one
    // closes the MIDI inputs, destroys every channel it minted, and calls
    // `System::close()`, which releases the audio device (the engine's own
    // docs: active rate / buffer / latency read `0` "pre-init, after close, or
    // [initOffline] path"). A fake that only flips [initialised] keeps
    // reporting the last opened device's rate and every channel the engine
    // ever created, so anything reading state after a close — an engine
    // restart, a second `start()` in one process, the diagnostics bundle —
    // sees a device that is not there (issue #399).
    _midiInputsOpen = false;
    channels.clear();
    // Deliberately *not* reset: `_nextChannelId`. `RealYseGateway` keeps
    // counting up across a close, so an id is never recycled onto a different
    // channel; a fake that restarted at 1 would hide a stale-id bug.
    _closeDeviceState();
    // Gauges and meters belong to the running engine. `close()` → device
    // manager close stores `cpuLoadEma = 0`, and dropping the master channel's
    // implementation makes `getPeakLinearPost()` / `getNumOutputs()` read `0`.
    //
    // `deviceStallTicks` is deliberately *not* reset here: the engine clears
    // `currentlyMissedCallbacks` in `initShared()` and on each `update()` that
    // sees a callback, never in `close()`, so the gauge keeps its last value
    // until the next init — where [_resetPerSessionGauges] now models it,
    // alongside the two other init-side resets `initShared()` performs (#402).
    cpuLoadValue = 0;
    masterPeakValue = 0;
    masterPeakOutputs = List<double>.filled(
      masterPeakOutputs.length,
      0,
      growable: true,
    );
    masterOutputCountValue = 0;
    // The test signal goes down with the system that was generating it.
    audioTestOn = false;
    // Left alone, because these record what a *test* asked for rather than
    // live engine state: [calls], [openedDevice] / [openLayout] (the explicit
    // opens the device rules are asserted through), [devices], and the
    // diagnostics facts ([engineVersionValue], [libraryPathValue]) which the
    // engine reports without a device open.
    //
    // Also left alone, but for the opposite reason — the engine leaves them
    // alone too: [masterVolumeValue] (a process-lifetime interface field; see
    // its doc for why the *applied* gain nonetheless goes back to unity),
    // [autoReconnectOn] and [deviceStallTicksValue]. All three are cleared by
    // the next `init()`, not by this call — see [_resetPerSessionGauges].
  }

  @override
  String get engineVersion => engineVersionValue;

  @override
  String? get libraryPath => libraryPathValue;

  /// The engine's enumeration cache: `null` until the first [init] fills it,
  /// then frozen for the life of this gateway. Measured against libyse 2.4.0 —
  /// the device list is empty before any init, is filled by `init()` only, then
  /// *survives* `close()`, a later `initOffline()` and a later `init()` alike
  /// (issues #403, #412). That survival is why #403's defect hid for so long: an
  /// in-process engine restart looks healthy, only a cold boot goes silent.
  List<AudioDeviceDescriptor>? _enumeratedCache;

  /// The hardware this fake fabricates — what is *physically in the machine*,
  /// which is not the same thing as what the engine can see (see
  /// [audioDevices]). Two entries share a name under different hosts, so tests
  /// exercise the name + host identity rule (design §3). Reassign to model other
  /// hardware (or an empty list); a test that needs the list readable through
  /// [audioDevices] must call [init] first, exactly as the app does.
  ///
  /// Reassigning is how a test plugs and unplugs an interface, so it carries two
  /// consequences and only two:
  ///
  /// - Hardware that disappears takes its open stream with it. When the device
  ///   that is live no longer appears in the new list, the active state drops to
  ///   "nothing is open", the way PortAudio errors the stream out and libyse's
  ///   device manager closes it (`open = false`, active buffer / latency stored
  ///   as `0`). A fake that let a test lose every device while
  ///   `activeAudioState()` still reported audio flowing would hand the health
  ///   monitor — and anything cross-checking `current` against the live state —
  ///   a machine that is silent and healthy at the same time (issues #398,
  ///   #399, #408).
  /// - Whether a subsequent [openAudioDevice] on a *cached* descriptor comes up
  ///   or fails. That is the only other thing hardware decides.
  ///
  /// What it explicitly does **not** do is change [audioDevices]: the engine
  /// enumerates once and never rescans (issue #412), so an unplugged device
  /// keeps its entry in the dropdown and a newly plugged one never gets one.
  List<AudioDeviceDescriptor> get devices => _devices;

  set devices(List<AudioDeviceDescriptor> value) {
    _devices = value;
    final live = _liveDevice;
    if (live == null) return;
    final stillThere = value.any(
      (d) => d.name == live.name && d.hostName == live.hostName,
    );
    if (!stillThere) _closeDeviceState();
  }

  /// The device the fake currently has "open" — whatever [init] or
  /// [openAudioDevice] last brought up, cleared whenever the live state is torn
  /// down. Distinct from [openedDevice], which records *explicit* opens for
  /// tests to assert on and survives a close.
  AudioDeviceDescriptor? _liveDevice;

  List<AudioDeviceDescriptor> _devices = const [
    AudioDeviceDescriptor(
      name: 'Fake Interface',
      hostName: 'WASAPI',
      inputChannelNames: ['In 1', 'In 2'],
      outputChannelNames: ['Out 1', 'Out 2'],
      sampleRates: [44100.0, 48000.0, 96000.0],
      bufferSizes: [64, 128, 256, 512],
      defaultBufferSize: 256,
      outputLatency: 256,
      inputLatency: 256,
    ),
    AudioDeviceDescriptor(
      name: 'Fake Interface',
      hostName: 'ASIO',
      inputChannelNames: ['In 1', 'In 2'],
      outputChannelNames: ['Out 1', 'Out 2', 'Out 3', 'Out 4'],
      sampleRates: [48000.0, 96000.0],
      bufferSizes: [128, 256],
      defaultBufferSize: 128,
      outputLatency: 128,
      inputLatency: 128,
    ),
  ];

  /// Device names that are present in [devices] but "fail to open" — lets tests
  /// drive the open-failure path (design §5) for a device that is visible yet
  /// refused by the engine.
  final Set<String> unopenableDeviceNames = {};

  /// The descriptor last passed to (or resolved by) [openAudioDevice], or `null`
  /// before any successful open. `<default>` opens record the resolved device.
  AudioDeviceDescriptor? openedDevice;

  /// The layout the last successful [openAudioDevice] opened with.
  SpeakerLayout? openLayout;

  /// The devices the engine can currently see: the cache [init] took, or an
  /// empty list before any (issue #403).
  ///
  /// **Not [devices].** This is a snapshot, not a view — it does not track the
  /// hardware, because libyse's does not either (issue #412). The list the
  /// settings dropdown is built from, and the list `openAudioDevice` resolves a
  /// name against, is whatever was plugged in when the engine started. To model
  /// a machine that enumerates different hardware, set [devices] *before*
  /// [init]; to model a genuinely fresh enumeration, build a new
  /// [FakeYseGateway] — a new process is what the real engine needs too.
  @override
  List<AudioDeviceDescriptor> audioDevices() => _enumeratedCache ?? const [];

  @override
  void openAudioDevice(
    AudioDeviceDescriptor? descriptor, {
    double? rate,
    int? buffer,
    SpeakerLayout layout = SpeakerLayout.auto,
  }) {
    // Resolved against the *enumerated* list, like `RealYseGateway`, which
    // searches `System.devices` — so an un-enumerated engine refuses every
    // open, including the platform default (issue #403).
    final visible = audioDevices();
    final AudioDeviceDescriptor target;
    if (descriptor == null) {
      if (visible.isEmpty) {
        throw const AudioDeviceException(
          'no platform-default audio device is available',
        );
      }
      target = visible.first;
    } else {
      final match = _find(descriptor.name, descriptor.hostName);
      if (match == null) {
        throw AudioDeviceException(
          'no audio device named "${descriptor.name}" on '
          '"${descriptor.hostName}" is available',
        );
      }
      target = match;
    }
    // A resolved target means `RealYseGateway` already ran
    // `closeCurrentDevice()` — the engine tears the running stream down
    // *before* it tries the new one — so a refused open leaves the machine
    // with no device at all: `open` goes false and the device manager stores
    // `activeBufferSize = 0` / `activeOutputLatency = 0`, with
    // `getActiveSampleRate()` gated on the same flag (libyse 2.4.0,
    // `portaudioDeviceManager.cpp`). A fake that kept reporting the previous
    // device's rate here would tell the health monitor the audio is fine
    // through a total loss, and would let `current` be checked against a live
    // state that agrees with it (issues #398, #399, #408).
    //
    // Two ways to be refused, and the first one is the ordinary one on real
    // hardware: the cached entry resolves fine but the interface behind it is
    // no longer in the machine, so `Pa_OpenStream` errors out on a stale index
    // (issue #412). `RealYseGateway` catches that by reading `activeSampleRate`
    // back as 0 and throwing, since the engine reports the failure as a log
    // line rather than a status (dart-yse #52).
    if (!_isPluggedIn(target)) {
      _closeDeviceState();
      throw AudioDeviceException(
        'engine reported no open device after opening "${target.name}" on '
        '"${target.hostName}" — it refused the device without an error',
      );
    }
    if (unopenableDeviceNames.contains(target.name)) {
      _closeDeviceState();
      throw AudioDeviceException('engine failed to open "${target.name}"');
    }
    calls.add(
      'openAudioDevice:${descriptor?.name ?? '<default>'}:'
      '${rate?.toStringAsFixed(0) ?? 'def'}:${buffer ?? 'def'}:'
      '${layout.wireName}',
    );
    openedDevice = target;
    openLayout = layout;
    _liveDevice = target;
    // Reflect the choice into the live state so activeAudioState() reads back
    // what was opened — overrides win, else the device's own defaults.
    activeSampleRateValue =
        rate ?? (target.sampleRates.isNotEmpty ? target.sampleRates.first : 0);
    activeBufferSizeValue = buffer ?? target.defaultBufferSize;
    activeOutputLatencyValue = target.outputLatency;
  }

  @override
  AudioDeviceState activeAudioState() => AudioDeviceState(
    sampleRate: activeSampleRateValue,
    bufferSize: activeBufferSizeValue,
    outputLatency: activeOutputLatencyValue,
  );

  /// The last auto-reconnect configuration the engine pushed — `null` until
  /// [setAutoReconnect] runs. Lets a test assert boot enabled it (design §4).
  bool? autoReconnectOn;
  int? autoReconnectDelayMs;

  @override
  void setAutoReconnect({required bool on, int delayMs = 1000}) {
    calls.add('setAutoReconnect:$on:$delayMs');
    autoReconnectOn = on;
    autoReconnectDelayMs = delayMs;
  }

  AudioDeviceDescriptor? _find(String name, String hostName) {
    for (final device in audioDevices()) {
      if (device.name == name && device.hostName == hostName) return device;
    }
    return null;
  }

  /// Whether the hardware behind a *cached* descriptor is still in the machine
  /// — the question the cache cannot answer and only an open can (issue #412).
  bool _isPluggedIn(AudioDeviceDescriptor device) => _devices.any(
    (d) => d.name == device.name && d.hostName == device.hostName,
  );

  @override
  void startUpdateTimer([
    Duration interval = const Duration(milliseconds: 16),
  ]) {
    calls.add('startUpdateTimer:${interval.inMilliseconds}');
  }

  @override
  double get cpuLoad => cpuLoadValue;

  @override
  int get deviceStallTicks => deviceStallTicksValue;

  @override
  set audioTest(bool on) {
    calls.add('audioTest:$on');
    audioTestOn = on;
  }

  /// What the gateway *reports* for the master volume — `Channel.master.volume`
  /// on the real side, which is the interface-side mirror `YSE::channel::volume`
  /// (`setVolume()` writes it "only used for getVolume").
  ///
  /// It has **process** lifetime, not session lifetime. The master channel is a
  /// plain member of the Meyers-singleton `CHANNEL::managerObject`, so its
  /// interface object outlives every init/close cycle; `System::close()` only
  /// destroys the *implementation* (which nulls `pimpl`), and `createGlobal()`
  /// on the next `init()` touches no interface field. Nothing anywhere resets
  /// `volume`. So this deliberately survives [close] — matching the engine.
  double masterVolumeValue = 1.0;

  /// What the master channel is *actually mixing at* — the impl-side
  /// `newVolume` / `lastVolume` that `adjustVolume()` ramps to.
  ///
  /// **This is the honest one, and it diverges from [masterVolumeValue] across a
  /// restart** (issue #402). Set 0.3, `close()`, `init()`: the engine renders at
  /// **1.0** (fresh impl, born at unity, no VOLUME message replayed) while
  /// `Channel.master.volume` still answers **0.3**. Neither value is wrong on
  /// its own; the getter is simply not a reading of the engine, it is a cache of
  /// the last write, and after a re-init it is a cache of a write that no longer
  /// applies to anything.
  ///
  /// The fake exposes both because a consumer that *seeds* itself from
  /// [masterVolume] — as `PhiEngine.start()` used to — reads back a value the
  /// engine is not honouring, and no single-valued fake can catch that. Assert
  /// on this to ask "is the master actually at the gain I think it is?".
  double appliedMasterVolume = 1.0;

  @override
  double get masterVolume => masterVolumeValue;

  @override
  set masterVolume(double value) {
    calls.add('masterVolume:${value.toStringAsFixed(3)}');
    // One write, both sides: `setVolume()` posts a VOLUME message to the impl
    // *and* caches the value on the interface. They only drift apart when the
    // impl is replaced underneath the cache — see [appliedMasterVolume].
    masterVolumeValue = value;
    appliedMasterVolume = value;
  }

  double masterPeakValue = 0;

  @override
  double get masterPeak => masterPeakValue;

  /// Number of speaker outputs the master channel feeds (design §6). Reassign
  /// to model a non-stereo layout (e.g. 6 for 5.1) before reading meters.
  int masterOutputCountValue = 2;

  /// Per-output post-fader master peaks — seed to drive the master strip's
  /// per-speaker meters. Out-of-range indices read `0`.
  List<double> masterPeakOutputs = [0, 0];

  @override
  int get masterOutputCount => masterOutputCountValue;

  @override
  double masterPeakOutput(int output) =>
      (output >= 0 && output < masterPeakOutputs.length)
      ? masterPeakOutputs[output]
      : 0;

  @override
  double get activeSampleRate => activeSampleRateValue;

  @override
  int get activeBufferSize => activeBufferSizeValue;

  @override
  int get activeOutputLatency => activeOutputLatencyValue;

  /// Public mirror of the per-channel state the engine writes into us.
  /// Tests can read this to assert the gateway received the right values,
  /// or seed `peak` to drive telemetry updates.
  final Map<int, FakeChannel> channels = {};
  int _nextChannelId = 1;

  @override
  int createChannel(String name, {int? parentId}) {
    final id = _nextChannelId++;
    calls.add('createChannel:$id:$name:${parentId ?? 'master'}');
    channels[id] = FakeChannel(name, parentId: parentId);
    return id;
  }

  @override
  void destroyChannel(int channelId) {
    calls.add('destroyChannel:$channelId');
    final gone = channels.remove(channelId);
    if (gone == null) return;
    // Destroying a channel is not a leaf operation (issue #402). `dispose()` is
    // documented only as "destroy the underlying native channel", but the engine
    // rewires *both* kinds of edge that pointed at the dying channel, and does
    // it on the audio thread at the `OBJECT_RELEASE → OBJECT_DELETE` transition,
    // before the impl can be freed — so nothing is ever left dangling.
    //
    // 1. **Children and attached sounds move up one level, to the destroyed
    //    channel's parent — not to master.** `childrenToParent()` walks
    //    `children` and then `sounds`, calling `parent->connect()` on each, and
    //    `parent` there is the dying channel's own parent. A strip three levels
    //    deep therefore lands two levels deep; only a child of a top-level group
    //    lands on master. The engine's tutorial states the contract outright:
    //    "Deleting a custom channel reparents its sounds and subchannels to the
    //    parent automatically." A fake that dropped the entry and left
    //    `parentId` pointing at a destroyed id let a test believe a whole subtree
    //    went silent with its group, when in fact it keeps playing one level up.
    //
    // 2. **Every send still aimed at it is severed.** `detachSends()` walks the
    //    return's `sendRegistry` and nulls `s->target` on each *sender's* slot,
    //    then clears the registry, so the slot stops contributing and is free to
    //    be re-wired. (The dying channel's own outgoing sends are unlinked from
    //    their targets in the same pass; here they simply go with the entry.)
    //    Modelled as removing the slot, because that is the effective state:
    //    the sender's interface-side mirror does keep a stale target id, but it
    //    is a graph key that is never dereferenced, and no gateway call reads
    //    it. Leaving a [FakeSend] in place with a `returnId` resolving to
    //    nothing let a test assert a send the engine had already disconnected.
    //
    // Note what is *not* here: no reference count, and no refusal. Destroying a
    // channel that still owns children, sounds and incoming sends is legal and
    // is the designed path.
    for (final ch in channels.values) {
      if (ch.parentId == channelId) ch.parentId = gone.parentId;
      ch.sends.removeWhere((_, send) => send.returnId == channelId);
    }
  }

  @override
  void moveChannel(int channelId, [int? parentId]) {
    calls.add('moveChannel:$channelId:${parentId ?? 'master'}');
    final ch = channels[channelId];
    if (ch != null) ch.parentId = parentId;
  }

  @override
  int createReturnChannel(String name, {int sendSlots = 4}) {
    final id = _nextChannelId++;
    calls.add('createReturnChannel:$id:$name:$sendSlots');
    channels[id] = FakeChannel(name, isReturn: true, sendSlots: sendSlots);
    return id;
  }

  @override
  double channelVolume(int channelId) => channels[channelId]?.volume ?? 0;

  @override
  void setChannelVolume(int channelId, double value) {
    calls.add('setChannelVolume:$channelId:${value.toStringAsFixed(3)}');
    final ch = channels[channelId];
    if (ch != null) ch.volume = value;
  }

  @override
  double channelPeak(int channelId) => channels[channelId]?.peak ?? 0;

  @override
  void setSend(
    int channelId,
    int slot,
    int returnId,
    double level,
    bool preFader,
  ) {
    calls.add(
      'setSend:$channelId:$slot:$returnId:'
      '${level.toStringAsFixed(3)}:$preFader',
    );
    final ch = channels[channelId];
    if (ch == null) return;
    // Mirror the engine's illegal-wiring rejection as a silent no-op (design
    // §4): the slot must be in range, the target must be an existing return,
    // and the edge must be neither a self-send nor close a cycle.
    if (!_isLegalSend(channelId, slot, returnId)) return;
    ch.sends[slot] = FakeSend(
      returnId: returnId,
      level: level,
      preFader: preFader,
    );
  }

  @override
  void setSendLevel(int channelId, int slot, double level) {
    calls.add('setSendLevel:$channelId:$slot:${level.toStringAsFixed(3)}');
    final send = channels[channelId]?.sends[slot];
    if (send != null) send.level = level;
  }

  @override
  void clearSend(int channelId, int slot) {
    calls.add('clearSend:$channelId:$slot');
    channels[channelId]?.sends.remove(slot);
  }

  @override
  int channelOutputCount(int channelId) =>
      channels[channelId]?.outputCount ?? 0;

  @override
  double channelPeakOutput(int channelId, int output) =>
      channels[channelId]?.peakOutput(output) ?? 0;

  @override
  double channelPeakPreOutput(int channelId, int output) =>
      channels[channelId]?.prePeakOutput(output) ?? 0;

  /// Whether wiring send [slot] of [channelId] to [returnId] would be accepted
  /// by the engine. Encodes the four rejection cases the engine logs as no-ops.
  bool _isLegalSend(int channelId, int slot, int returnId) {
    final ch = channels[channelId];
    if (ch == null) return false;
    if (slot < 0 || slot >= ch.sendSlots) return false; // out-of-range slot
    if (returnId == channelId) return false; // self-send
    final target = channels[returnId];
    if (target == null || !target.isReturn) return false; // non-return target
    if (_sendReaches(returnId, channelId)) return false; // would close a cycle
    return true;
  }

  /// Whether [from] can already reach [goal] by following existing send edges —
  /// used to reject a return → return edge that would close a cycle.
  bool _sendReaches(int from, int goal, [Set<int>? seen]) {
    if (from == goal) return true;
    seen ??= {};
    if (!seen.add(from)) return false;
    final ch = channels[from];
    if (ch == null) return false;
    for (final send in ch.sends.values) {
      if (_sendReaches(send.returnId, goal, seen)) return true;
    }
    return false;
  }

  /// Close the internal stream controller. Call from test teardown to keep
  /// `flutter test --reporter expanded` from leaking pending subscriptions.
  Future<void> dispose() => _midiActivity.close();
}

/// Per-channel state the fake records and the engine writes to.
class FakeChannel {
  FakeChannel(
    this.name, {
    this.parentId,
    this.isReturn = false,
    int sendSlots = 4,
  }) : sendSlots = isReturn ? sendSlots : 4;

  final String name;
  double volume = 1.0;
  double peak = 0.0;

  /// Parent channel id in the mix tree, or `null` for a child of master.
  /// Meaningless for a return (returns sit outside the tree).
  int? parentId;

  /// Whether this channel is a return bus ([createReturnChannel]) rather than
  /// an ordinary mix-tree channel.
  final bool isReturn;

  /// Number of aux-send slots. Ordinary channels get the engine default of
  /// four; a return fixes its own count at creation.
  final int sendSlots;

  /// Number of speaker outputs this channel feeds. Reassign to model a
  /// non-stereo layout before reading per-output meters.
  int outputCount = 2;

  /// Per-output post- and pre-fader peaks — seed to drive per-speaker meters.
  /// Out-of-range indices read `0`.
  List<double> peakOutputs = [0, 0];
  List<double> prePeakOutputs = [0, 0];

  /// Active sends keyed by slot index.
  final Map<int, FakeSend> sends = {};

  double peakOutput(int output) =>
      (output >= 0 && output < peakOutputs.length) ? peakOutputs[output] : 0;

  double prePeakOutput(int output) =>
      (output >= 0 && output < prePeakOutputs.length)
      ? prePeakOutputs[output]
      : 0;
}

/// One wired aux send: the target return, its level, and pre/post-fader tap.
class FakeSend {
  FakeSend({
    required this.returnId,
    required this.level,
    required this.preFader,
  });

  final int returnId;
  double level;
  final bool preFader;
}
