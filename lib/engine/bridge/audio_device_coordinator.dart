import '../../domain/project/app_settings/audio_settings.dart';
import 'audio_device_descriptor.dart';
import 'audio_device_exception.dart';
import 'audio_device_notice.dart';
import 'audio_device_recovery.dart';
import 'audio_device_state.dart';
import 'audio_recovery_status.dart';
import 'yse_gateway.dart';

/// Drives the device rules (design `docs/design/settings-and-devices.md` §5,
/// §9.3) over a [YseGateway]: [boot] brings audio up on the platform default,
/// and [switchTo] moves it to a chosen device — both when the stored preference
/// arrives at launch and when the performer picks one in the settings window.
/// There is deliberately no second, settings-carrying boot entry point; see
/// [boot] for why the engine cannot offer one (issues #403, #405).
///
/// Pure orchestration — it never touches `package:yse` or Flutter, so every
/// fallback path is unit-tested end to end against the fake gateway. It holds a
/// single piece of state, [current]: the settings that describe whichever device
/// is open right now — or `null` when none is (issue #408) — which a failed live
/// switch reverts to. It **never writes the stored preference** — that stays the
/// caller's (`AppSettingsController`'s) job, so an interface that wasn't plugged
/// in yet can't erase its configuration.
///
/// It also **supervises recovery** from a total loss (issue #410): whenever it
/// ends up with nothing open it arms an [AudioDeviceRecovery], a bounded run of
/// re-open attempts, and stands it down as soon as a device is back. That is
/// Phi's job rather than the engine's — see [AudioDeviceRecovery] for what
/// libyse's own `setAutoReconnect` really does and why boot now turns it off.
/// Owning a timer makes this class disposable: call [dispose] with the engine.
class AudioDeviceCoordinator {
  /// Binds the coordinator to its [gateway]. [onNotice] receives every
  /// non-blocking notice raised by a fallback (design §5) — `null` drops them.
  /// [recoverySchedule] overrides the retry cadence (tests drive it fast).
  AudioDeviceCoordinator(
    this._gateway, {
    void Function(AudioDeviceNotice)? onNotice,
    List<Duration> recoverySchedule = AudioDeviceRecovery.defaultSchedule,
  }) : _onNotice = onNotice {
    _recovery = AudioDeviceRecovery(
      attempt: _attemptRecovery,
      onExhausted: _onRecoveryExhausted,
      schedule: recoverySchedule,
    );
  }

  final YseGateway _gateway;
  final void Function(AudioDeviceNotice)? _onNotice;
  late final AudioDeviceRecovery _recovery;

  AudioSettings? _current;

  /// The device the app is *trying* to be on — the last settings handed to
  /// [switchTo], or `null` when nothing has been asked for and the platform
  /// default is all there is. Distinct from [current], which is what is open;
  /// this is what a recovery run reaches for first.
  AudioSettings? _intended;

  /// The settings describing the device currently open — what a failed live
  /// switch reverts to (design §9.3). Its stored rate / buffer are normalised to
  /// what the device actually accepted (an unsupported override reads back as
  /// `null`, i.e. the device default).
  ///
  /// **`null` means no device is open at all** (issue #408) — the total loss a
  /// [AudioNoticeKind.noAudioDevice] notice announces, or a [boot] on a machine
  /// whose engine came up without a device. It is deliberately *not* spelled as
  /// an empty [AudioSettings]: that value already means "the platform default is
  /// open", which is exactly the state a reader would confuse it with. Readers
  /// must render "no device" rather than a name — the diagnostics rows and the
  /// pasted report are where a performer goes to find out what happened, and a
  /// stale name there is the one lie that costs a debugging session.
  AudioSettings? get current => _current;

  /// What the recovery supervisor is doing — idle while a device is open,
  /// retrying through a loss, or given up (issue #410). The status-bar chip and
  /// the diagnostics row read this to tell "coming back" from "your move".
  AudioRecoveryStatus get recovery => _recovery.status;

  /// Brings audio up on the platform default: `init()` (design §4, §5). Takes no
  /// settings — the stored device is applied afterwards, as a [switchTo] once the
  /// settings store has loaded (`Workstation._startProject`).
  ///
  /// That ordering is not a shortcut, it is the only one the engine supports.
  /// **Devices are enumerated only while opening one** (issue #403):
  /// `initOffline()` — which design §5 originally specified, so that boot never
  /// opened a device the performer hadn't asked for — takes
  /// `deviceManager::init(false)`, skipping both `Pa_Initialize()` and
  /// `updateDeviceList()`. Measured against libyse 2.4.0 on Windows:
  /// `initOffline()` then `audioDevices()` returns **0** devices (and `init()`
  /// afterwards is a no-op, the engine refusing a second init), where `init()`
  /// returns 19. So *any* boot has to open the platform default before it can
  /// resolve a stored name, which makes a settings-carrying `boot` and an
  /// `init()` + [switchTo] literally the same sequence — this class used to
  /// implement both, and the branch the app never ran is where #403's defect sat
  /// (issue #405). Revisit if the engine grows an enumerate-without-opening call
  /// (dart-yse #51); until then there is one boot path and the app runs it.
  void boot() {
    _gateway.init();
    // `init()` brings the platform default up with it — but only on a machine
    // that *has* one. Ask the engine what actually came up rather than assuming,
    // so [current] never claims the default device on a box with no audio
    // hardware (issue #408).
    _current = _gateway.activeAudioState() == AudioDeviceState.none
        ? null
        : const AudioSettings();
    // Design §4 used to enable the engine's auto-reconnect here. It is off
    // (issue #410): measured, it reopens `Pa_GetDefaultOutputDevice()` rather
    // than the device that was lost, discards the chosen buffer size, retries on
    // every 16 ms control tick with no backoff once armed, and reads its
    // `delayMs` as a tick count. Phi supervises instead — see
    // [AudioDeviceRecovery]. Called explicitly rather than left to the engine's
    // own default so the decision is visible on the wire.
    _gateway.setAutoReconnect(on: false);
    // A machine whose engine came up with no device at all is already the state
    // recovery exists for — an interface that is slow to enumerate at login is
    // the ordinary cause — so start trying rather than sitting silent.
    if (_current == null) _recovery.arm();
  }

  /// Applies a device change (design §5, §9.3): close the open device and open
  /// [desired]. This is both the launch-time apply of the stored preference —
  /// the shell calls it once settings have loaded, over the platform default
  /// [boot] left running — and the live change from the settings window. On any
  /// failure the previous working device is kept (target missing) or restored
  /// (open failed), a notice is raised, and `false` is returned so the caller
  /// knows **not** to persist [desired] — the stored choice updates only on
  /// success. Returns `true` when [desired] is open (including a no-op when it is
  /// already the current device).
  ///
  /// When the revert fails too — every device gone — a
  /// [AudioNoticeKind.noAudioDevice] notice is raised and [current] becomes
  /// `null`, because at that point the engine is on nothing (issue #408), and a
  /// bounded recovery run is armed to try to get it back (issue #410). Any
  /// outcome that *does* leave a device open stands that run down.
  bool switchTo(AudioSettings desired) {
    // Remember what was asked for even when it fails: a recovery run reaches for
    // the performer's device first, and after a total loss [current] is `null`,
    // so this is the only record of what they wanted.
    _intended = desired;
    final descriptor = desired.outputDevice == null
        ? null
        : _resolve(desired.outputHost, desired.outputDevice);

    // Target device is gone — never disturb the open device (design §9.3 keeps
    // the last working state), just notify and report failure. The message names
    // what is being kept, because this same line greets an unplugged interface at
    // launch, where "the current device" is the platform default the engine came
    // up on and the performer has picked nothing yet (issue #405).
    if (desired.outputDevice != null && descriptor == null) {
      final current = _current;
      _notify(
        AudioNoticeKind.switchReverted,
        current == null
            ? 'Audio device "${desired.outputDevice}" is not available — no '
                  'audio output device is open.'
            : 'Audio device "${desired.outputDevice}" is not available — '
                  'staying on ${_nameOf(current)}.',
      );
      // Nothing is open and the performer's pick isn't there either: keep
      // trying, with a fresh budget, now that we know which device they want.
      if (current == null) _recovery.arm();
      return false;
    }

    // Already on this exact target — avoid a needless dropout (e.g. re-applying
    // "default" at launch when the engine already opened it).
    if (desired == _current) return true;

    final previous = _current;
    if (_open(descriptor, desired)) {
      _recovery.cancel();
      return true;
    }

    // A failed open normally leaves the machine device-less: the gateway closes
    // the running device before it attempts the new one (`closeCurrentDevice()`
    // + `openDevice()`). Not always, though — a target that resolves to no
    // device at all is refused before the close. So ask the engine what is
    // actually running instead of assuming, and let [current] follow it: the two
    // can then never disagree (issue #408).
    _current = _gateway.activeAudioState() == AudioDeviceState.none
        ? null
        : previous;

    if (previous == null) {
      // Nothing was open to revert to: a retry that failed while the machine was
      // already in a total loss. There is no "previous working device" to name.
      _notify(
        AudioNoticeKind.noAudioDevice,
        'No audio output device could be opened.',
      );
      _recovery.arm();
      return false;
    }

    // Reopen what was running to honour "revert to the previous working device"
    // (design §9.3).
    _notify(
      AudioNoticeKind.switchReverted,
      'Audio device "${desired.outputDevice ?? 'default'}" could not be opened — '
      'reverting to ${_nameOf(previous)}.',
    );
    if (_reopen(previous)) {
      // [_reopen] put the reopened device into [current] itself.
      _recovery.cancel();
    } else {
      // Both gone — the total loss. [current] goes to `null`: reporting
      // `previous` here is what made the diagnostics section name a device the
      // engine was not on (issue #408).
      _current = null;
      _notify(
        AudioNoticeKind.noAudioDevice,
        'No audio output device could be opened.',
      );
      _recovery.arm();
    }
    return false;
  }

  /// Notices a device that went away **on its own** — the ordinary way a
  /// performer meets this, by pulling a USB interface mid-set (issue #410).
  /// Called on the engine's telemetry tick (`PhiEngine._emit`), because that is
  /// the only way to find out: libyse has no device-change event of any kind,
  /// and `activeSampleRate == 0` is its documented "nothing is open" sentinel.
  ///
  /// Without this, recovery would only ever arm from a *switch* that failed —
  /// and an unplugged cable involves no switch at all, so the one case the
  /// performer actually hits would be the one case nothing retried.
  ///
  /// Idempotent by construction: it fires only on the edge where [current] still
  /// names a device the engine has stopped reporting, and arming clears
  /// [current], so a standing loss re-arms nothing.
  void observeLiveState() {
    if (_current == null) return;
    if (_gateway.activeAudioState() != AudioDeviceState.none) return;
    _current = null;
    _notify(
      AudioNoticeKind.noAudioDevice,
      'The audio output device stopped — trying to bring audio back.',
    );
    _recovery.arm();
  }

  /// One recovery attempt (issue #410): reach for the device the performer
  /// actually wants, then settle for the platform default. Quiet by design — a
  /// run makes up to eight of these, and eight "unsupported sample rate" toasts
  /// while the audio is already gone would bury the one message that matters.
  ///
  /// Returns `true` as soon as a device is open, which is what ends the run.
  /// "Open" here is the engine's own answer: [_open] only reports success once
  /// the gateway has confirmed a stream came up (dart-yse #52), so a run cannot
  /// end on a device that merely failed to complain.
  bool _attemptRecovery() {
    final intended = _intended;
    if (intended != null && _reopen(intended)) return true;
    // The default is worth a separate try — the performer's interface may still
    // be missing while the built-in output is perfectly available. Skipped when
    // it *is* what was asked for, so an attempt is never spent twice.
    if (intended != const AudioSettings() && _reopen(const AudioSettings())) {
      return true;
    }
    return false;
  }

  /// Announces that the retry budget is spent (issue #410). Recovery is manual
  /// from here: the chip settles on NO AUDIO and the message says where to go,
  /// rather than leaving a performer watching a spinner that will never stop.
  void _onRecoveryExhausted() => _notify(
    AudioNoticeKind.noAudioDevice,
    'No audio output device could be opened after ${_recovery.limit} attempts '
    '— choose an output device in Settings › Audio.',
  );

  /// Stands any recovery run down and releases its timer. Call with the engine
  /// ([PhiEngine.dispose]); a disposed coordinator never retries again.
  void dispose() => _recovery.dispose();

  /// Stands any recovery run down without disposing — the engine stopped, so
  /// there is no device to recover until it starts again.
  void stopRecovery() => _recovery.cancel();

  /// Opens [descriptor] (or the platform default when `null`) with [settings]'
  /// validated rate / buffer and layout, updating [current] on success. Returns
  /// `false` when the gateway refused the open ([AudioDeviceException]).
  ///
  /// [quiet] suppresses the rate / buffer fallback notices — used by the paths
  /// that re-open a device the performer already agreed to (a revert, a recovery
  /// attempt), where the message has either been said already or would be said
  /// eight times over.
  bool _open(
    AudioDeviceDescriptor? descriptor,
    AudioSettings settings, {
    bool quiet = false,
  }) {
    final rate = descriptor == null
        ? settings.sampleRate?.toDouble()
        : _validRate(descriptor, settings.sampleRate, quiet: quiet);
    final buffer = descriptor == null
        ? settings.bufferSize
        : _validBuffer(descriptor, settings.bufferSize, quiet: quiet);
    try {
      _gateway.openAudioDevice(
        descriptor,
        rate: rate,
        buffer: buffer,
        layout: settings.layout,
      );
      _current = AudioSettings(
        outputHost: descriptor?.hostName,
        outputDevice: descriptor?.name,
        sampleRate: rate?.toInt(),
        bufferSize: buffer,
        layout: settings.layout,
      );
      return true;
    } on AudioDeviceException {
      return false;
    }
  }

  /// Resolves [settings]' device and opens it quietly — the revert of a failed
  /// switch (design §9.3) and each attempt of a recovery run (issue #410). Both
  /// re-open something the performer already chose, so neither says anything the
  /// switch itself has not already said. Updates [current] through [_open] on
  /// success; returns `false` when the device is gone or refuses.
  bool _reopen(AudioSettings settings) {
    final descriptor = settings.outputDevice == null
        ? null
        : _resolve(settings.outputHost, settings.outputDevice);
    if (settings.outputDevice != null && descriptor == null) return false;
    return _open(descriptor, settings, quiet: true);
  }

  /// The device matching [name] + [host] in the current list, or `null` when
  /// none does. A `null` [host] matches on name alone (a hand-edited settings
  /// file may omit the host).
  AudioDeviceDescriptor? _resolve(String? host, String? name) {
    for (final device in _gateway.audioDevices()) {
      if (device.name == name && (host == null || device.hostName == host)) {
        return device;
      }
    }
    return null;
  }

  /// The stored [rate] as a device-accepted value, or `null` (device default)
  /// with a notice when the device no longer reports it (design §5).
  double? _validRate(
    AudioDeviceDescriptor device,
    int? rate, {
    bool quiet = false,
  }) {
    if (rate == null) return null;
    if (device.sampleRates.contains(rate.toDouble())) return rate.toDouble();
    if (quiet) return null;
    _notify(
      AudioNoticeKind.unsupportedSampleRate,
      'Sample rate $rate Hz is not supported by "${device.name}" — using its '
      'default rate.',
    );
    return null;
  }

  /// The stored [buffer] as a device-accepted value, or `null` (device default)
  /// with a notice when the device no longer reports it (design §5).
  int? _validBuffer(
    AudioDeviceDescriptor device,
    int? buffer, {
    bool quiet = false,
  }) {
    if (buffer == null) return null;
    if (device.bufferSizes.contains(buffer)) return buffer;
    if (quiet) return null;
    _notify(
      AudioNoticeKind.unsupportedBufferSize,
      'Buffer size $buffer is not supported by "${device.name}" — using its '
      'default buffer.',
    );
    return null;
  }

  /// How an open device reads in a notice — its name, or "the default device"
  /// when nothing was chosen (the state `boot` leaves behind). Only ever called
  /// with settings that describe a device that *is* open; "no device" is spelled
  /// out by the caller, because it changes the whole sentence.
  String _nameOf(AudioSettings settings) => settings.outputDevice != null
      ? '"${settings.outputDevice}"'
      : 'the default device';

  void _notify(AudioNoticeKind kind, String message) =>
      _onNotice?.call(AudioDeviceNotice(kind, message));
}
