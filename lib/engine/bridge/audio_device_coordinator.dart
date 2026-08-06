import '../../domain/project/app_settings/audio_settings.dart';
import 'audio_device_descriptor.dart';
import 'audio_device_exception.dart';
import 'audio_device_notice.dart';
import 'yse_gateway.dart';

/// Drives the boot-from-settings and live-switch device rules (design
/// `docs/design/settings-and-devices.md` §5, §9.3) over a [YseGateway].
///
/// Pure orchestration — it never touches `package:yse` or Flutter, so every
/// fallback path is unit-tested end to end against the fake gateway. It holds a
/// single piece of state, [current]: the settings that describe whichever device
/// is open right now, which a failed live switch reverts to. It **never writes
/// the stored preference** — that stays the caller's (`AppSettingsController`'s)
/// job, so an interface that wasn't plugged in yet can't erase its configuration.
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

  AudioSettings _current = const AudioSettings();

  /// The settings describing the device currently open — what a failed live
  /// switch reverts to (design §9.3). Its stored rate / buffer are normalised to
  /// what the device actually accepted (an unsupported override reads back as
  /// `null`, i.e. the device default).
  AudioSettings get current => _current;

  /// Boots the engine from [settings] (design §5):
  ///
  /// - **no stored device** → `init()` (the platform default), exactly as before
  ///   settings existed;
  /// - **a stored device** → `init()` too, then resolve the stored host + name
  ///   against the live device list and open it with its (validated) rate /
  ///   buffer overrides and layout. A missing device, an open failure, or an
  ///   unsupported rate / buffer each falls back (to the default device, or the
  ///   device's own default rate / buffer) and raises a notice.
  ///
  /// Both branches `init()` because **the engine only enumerates devices when it
  /// opens one** (issue #403). `initOffline()` — which design §5 originally
  /// specified for the stored-device path, to avoid opening the wrong device for
  /// a moment — takes `deviceManager::init(false)`, which skips both
  /// `Pa_Initialize()` and `updateDeviceList()`. Measured against libyse 2.4.0 on
  /// Windows: `initOffline()` then `audioDevices()` returns **0** devices (and
  /// `init()` afterwards is a no-op, the engine refusing a second init), where
  /// `init()` returns 19. On the old path every stored device therefore resolved
  /// to "not available", the default fallback searched the same empty list, and
  /// the app booted silent — the one outcome design §5 exists to prevent. The
  /// brief platform-default open is the price; restoring the offline boot needs
  /// an enumerate-without-opening call in the engine (dart-yse #51).
  ///
  /// Enables 1 s engine auto-reconnect regardless (design §4). The stored
  /// [settings] are only ever read here, never rewritten — the keep-preference
  /// rule holds by construction.
  void boot(AudioSettings settings) {
    _gateway.init();
    _current = const AudioSettings();
    if (settings.outputDevice != null) {
      _openStoredOrFallBackToDefault(settings);
    }
    _gateway.setAutoReconnect(on: true, delayMs: _reconnectDelayMs);
  }

  /// Applies a live device change (design §5 "Live change", §9.3): close the open
  /// device and open [desired]. On any failure the previous working device is
  /// kept (target missing) or restored (open failed), a notice is raised, and
  /// `false` is returned so the caller knows **not** to persist [desired] — the
  /// stored choice updates only on success. Returns `true` when [desired] is open
  /// (including a no-op when it is already the current device).
  bool switchTo(AudioSettings desired) {
    final descriptor = desired.outputDevice == null
        ? null
        : _resolve(desired.outputHost, desired.outputDevice);

    // Target device is gone — never disturb the open device (design §9.3 keeps
    // the last working state), just notify and report failure.
    if (desired.outputDevice != null && descriptor == null) {
      _notify(
        AudioNoticeKind.switchReverted,
        'Audio device "${desired.outputDevice}" is not available — keeping the '
        'current device.',
      );
      return false;
    }

    // Already on this exact target — avoid a needless dropout (e.g. re-applying
    // "default" at launch when the engine already opened it).
    if (desired == _current) return true;

    final previous = _current;
    if (_open(descriptor, desired)) return true;

    // The open closed the previous device before it failed, so reopen it to
    // honour "revert to the previous working device" (design §9.3).
    _notify(
      AudioNoticeKind.switchReverted,
      'Audio device "${desired.outputDevice ?? 'default'}" could not be opened — '
      'reverting to the previous device.',
    );
    if (_reopen(previous)) {
      _current = previous;
    } else {
      _notify(
        AudioNoticeKind.noAudioDevice,
        'No audio output device could be opened.',
      );
    }
    return false;
  }

  /// Opens the stored device (design §5), falling back to the platform default
  /// with a notice when it is missing or refuses to open. Runs only on the boot
  /// path, after [boot] has already `init()`-ed the engine — which is what makes
  /// the device list it resolves against non-empty (issue #403).
  void _openStoredOrFallBackToDefault(AudioSettings settings) {
    final descriptor = _resolve(settings.outputHost, settings.outputDevice);
    if (descriptor == null) {
      _notify(
        AudioNoticeKind.deviceUnavailable,
        'Audio device "${settings.outputDevice}"'
        '${settings.outputHost != null ? ' on "${settings.outputHost}"' : ''} '
        'is not available — using the default device instead.',
      );
      _openDefaultOrNone(settings);
      return;
    }
    if (!_open(descriptor, settings)) {
      _notify(
        AudioNoticeKind.deviceOpenFailed,
        'Audio device "${descriptor.name}" could not be opened — using the '
        'default device instead.',
      );
      _openDefaultOrNone(settings);
    }
  }

  /// Opens the platform-default device with [settings]' layout, or raises a
  /// [AudioNoticeKind.noAudioDevice] notice and leaves the engine device-less
  /// when even the default cannot be opened (no devices at all).
  void _openDefaultOrNone(AudioSettings settings) {
    try {
      _gateway.openAudioDevice(null, layout: settings.layout);
      _current = AudioSettings(layout: settings.layout);
    } on AudioDeviceException {
      _notify(
        AudioNoticeKind.noAudioDevice,
        'No audio output device is available.',
      );
      _current = const AudioSettings();
    }
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

  void _notify(AudioNoticeKind kind, String message) =>
      _onNotice?.call(AudioDeviceNotice(kind, message));
}
