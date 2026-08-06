import '../../domain/project/app_settings/audio_settings.dart';
import 'audio_device_descriptor.dart';
import 'audio_device_exception.dart';
import 'audio_device_notice.dart';
import 'audio_device_state.dart';
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
class AudioDeviceCoordinator {
  /// Binds the coordinator to its [gateway]. [onNotice] receives every
  /// non-blocking notice raised by a fallback (design §5) — `null` drops them.
  AudioDeviceCoordinator(
    this._gateway, {
    void Function(AudioDeviceNotice)? onNotice,
  }) : _onNotice = onNotice;

  final YseGateway _gateway;
  final void Function(AudioDeviceNotice)? _onNotice;

  /// The 1 s auto-reconnect delay enabled at boot (design §4) — the engine
  /// re-opens a device that disappears. Not a setting in v1.
  static const int _reconnectDelayMs = 1000;

  AudioSettings? _current;

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

  /// Brings audio up on the platform default: `init()` plus 1 s engine
  /// auto-reconnect (design §4, §5). Takes no settings — the stored device is
  /// applied afterwards, as a [switchTo] once the settings store has loaded
  /// (`Workstation._startProject`).
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
    _gateway.setAutoReconnect(on: true, delayMs: _reconnectDelayMs);
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
  /// `null`, because at that point the engine is on nothing (issue #408).
  bool switchTo(AudioSettings desired) {
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
      return false;
    }

    // Already on this exact target — avoid a needless dropout (e.g. re-applying
    // "default" at launch when the engine already opened it).
    if (desired == _current) return true;

    final previous = _current;
    if (_open(descriptor, desired)) return true;

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
      _current = previous;
    } else {
      // Both gone — the total loss. [current] goes to `null`: reporting
      // `previous` here is what made the diagnostics section name a device the
      // engine was not on (issue #408).
      _current = null;
      _notify(
        AudioNoticeKind.noAudioDevice,
        'No audio output device could be opened.',
      );
    }
    return false;
  }

  /// Opens [descriptor] (or the platform default when `null`) with [settings]'
  /// validated rate / buffer and layout, updating [current] on success. Returns
  /// `false` when the gateway refused the open ([AudioDeviceException]).
  bool _open(AudioDeviceDescriptor? descriptor, AudioSettings settings) {
    final rate = descriptor == null
        ? settings.sampleRate?.toDouble()
        : _validRate(descriptor, settings.sampleRate);
    final buffer = descriptor == null
        ? settings.bufferSize
        : _validBuffer(descriptor, settings.bufferSize);
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

  /// Reopens [settings]' device to revert a failed switch (design §9.3). Unlike
  /// [_open] it raises no rate / buffer notices — these settings already opened
  /// cleanly once. Returns `false` when the device can no longer be opened.
  bool _reopen(AudioSettings settings) {
    final descriptor = settings.outputDevice == null
        ? null
        : _resolve(settings.outputHost, settings.outputDevice);
    if (settings.outputDevice != null && descriptor == null) return false;
    try {
      _gateway.openAudioDevice(
        descriptor,
        rate: settings.sampleRate?.toDouble(),
        buffer: settings.bufferSize,
        layout: settings.layout,
      );
      return true;
    } on AudioDeviceException {
      return false;
    }
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
  double? _validRate(AudioDeviceDescriptor device, int? rate) {
    if (rate == null) return null;
    if (device.sampleRates.contains(rate.toDouble())) return rate.toDouble();
    _notify(
      AudioNoticeKind.unsupportedSampleRate,
      'Sample rate $rate Hz is not supported by "${device.name}" — using its '
      'default rate.',
    );
    return null;
  }

  /// The stored [buffer] as a device-accepted value, or `null` (device default)
  /// with a notice when the device no longer reports it (design §5).
  int? _validBuffer(AudioDeviceDescriptor device, int? buffer) {
    if (buffer == null) return null;
    if (device.bufferSizes.contains(buffer)) return buffer;
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
