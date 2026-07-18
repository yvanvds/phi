import 'speaker_layout.dart';

/// The audio section of `settings.json` (design
/// `docs/design/settings-and-devices.md` §3) — which output device to open, and
/// how.
///
/// A plain immutable value type in the same style as `AppSettings`: it
/// (de)serialises to a JSON map, compares by value, and its [fromJson] tolerates
/// missing or malformed keys (an older or hand-edited file) by falling back to
/// defaults.
///
/// Devices are identified by **name + host**, never by index — indices shift
/// with every reboot and USB replug, so the pair is the stable identity (§3).
/// The same interface under WASAPI and under ASIO is two distinct choices, hence
/// both fields. [sampleRate] and [bufferSize] are *optional overrides*: `null`
/// means "use the device default"; a stored value is validated against the
/// device's reported lists at apply time (a later issue), not here.
class AudioSettings {
  /// Builds the audio settings. All fields are optional; the all-default
  /// instance (`const AudioSettings()`) means "open the platform default device
  /// with its own defaults", the pre-settings behaviour.
  const AudioSettings({
    this.outputHost,
    this.outputDevice,
    this.sampleRate,
    this.bufferSize,
    this.layout = SpeakerLayout.defaultLayout,
  });

  /// Reads the audio section from a decoded map, tolerating missing or malformed
  /// keys with defaults. A non-positive [sampleRate]/[bufferSize] is treated as
  /// absent (fall back to the device default).
  factory AudioSettings.fromJson(Map<String, Object?> json) {
    final host = json['outputHost'];
    final device = json['outputDevice'];
    final rate = json['sampleRate'];
    final buffer = json['bufferSize'];
    return AudioSettings(
      outputHost: host is String ? host : null,
      outputDevice: device is String ? device : null,
      sampleRate: rate is num && rate > 0 ? rate.toInt() : null,
      bufferSize: buffer is num && buffer > 0 ? buffer.toInt() : null,
      layout: SpeakerLayout.fromWire(json['layout']),
    );
  }

  /// The audio host/API of the chosen output device (e.g. `ASIO`, `WASAPI`), or
  /// `null` when no device has been chosen (use the platform default).
  final String? outputHost;

  /// The chosen output device's name, or `null` for the platform default.
  final String? outputDevice;

  /// An override for the device's sample rate, or `null` to use its default.
  final int? sampleRate;

  /// An override for the device's buffer size, or `null` to use its default.
  final int? bufferSize;

  /// The speaker layout the device is opened with (default [SpeakerLayout.auto]).
  final SpeakerLayout layout;

  /// The section as the JSON map nested under `audio` in `settings.json`. Absent
  /// optional fields are omitted (absent = default) so a round-trip is an
  /// identity; [layout] is always written.
  Map<String, Object?> toJson() => {
    if (outputHost != null) 'outputHost': outputHost,
    if (outputDevice != null) 'outputDevice': outputDevice,
    if (sampleRate != null) 'sampleRate': sampleRate,
    if (bufferSize != null) 'bufferSize': bufferSize,
    'layout': layout.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is AudioSettings &&
      other.outputHost == outputHost &&
      other.outputDevice == outputDevice &&
      other.sampleRate == sampleRate &&
      other.bufferSize == bufferSize &&
      other.layout == layout;

  @override
  int get hashCode =>
      Object.hash(outputHost, outputDevice, sampleRate, bufferSize, layout);

  @override
  String toString() =>
      'AudioSettings(outputHost: $outputHost, outputDevice: $outputDevice, '
      'sampleRate: $sampleRate, bufferSize: $bufferSize, layout: ${layout.name})';
}
