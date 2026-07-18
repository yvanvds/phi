/// A pure, FFI-free descriptor of an audio device the engine can see (design
/// `docs/design/settings-and-devices.md` §4, §7).
///
/// [YseGateway.audioDevices] hands these out instead of `package:yse`'s
/// `Device`, so nothing above the bridge ever touches an FFI type — the settings
/// window builds its device dropdown, and its rate / buffer / layout choices,
/// entirely from these value objects. Devices are identified by **name + host**
/// (§3): the same physical interface under WASAPI and under ASIO is two distinct
/// choices, hence both fields.
///
/// Immutable and compared by value (list fields included), so a re-enumeration
/// that reports the same hardware equals the previous descriptor and the UI need
/// not rebuild.
class AudioDeviceDescriptor {
  /// Builds a descriptor. Only [name] and [hostName] are required — the stable
  /// identity; the reported lists default to empty and the scalars to zero for a
  /// device that reports nothing.
  const AudioDeviceDescriptor({
    required this.name,
    required this.hostName,
    this.inputChannelNames = const [],
    this.outputChannelNames = const [],
    this.sampleRates = const [],
    this.bufferSizes = const [],
    this.defaultBufferSize = 0,
    this.outputLatency = 0,
    this.inputLatency = 0,
  });

  /// Device name as reported by the host (e.g. `Fireface UCX`).
  final String name;

  /// Host / driver name: `ASIO`, `WASAPI`, `ALSA`, `JACK`, ...
  final String hostName;

  /// Input channel names the device exposes, in order.
  final List<String> inputChannelNames;

  /// Output channel names the device exposes, in order.
  final List<String> outputChannelNames;

  /// Every sample rate the device reports as supported, in Hz.
  final List<double> sampleRates;

  /// Every buffer size (frames-per-callback) the device reports as supported.
  final List<int> bufferSizes;

  /// The device's own default buffer size — the "device default" the rate /
  /// buffer dropdowns offer as their first entry (design §6).
  final int defaultBufferSize;

  /// Reported output latency, in samples.
  final int outputLatency;

  /// Reported input latency, in samples.
  final int inputLatency;

  @override
  bool operator ==(Object other) =>
      other is AudioDeviceDescriptor &&
      other.name == name &&
      other.hostName == hostName &&
      _listEquals(other.inputChannelNames, inputChannelNames) &&
      _listEquals(other.outputChannelNames, outputChannelNames) &&
      _listEquals(other.sampleRates, sampleRates) &&
      _listEquals(other.bufferSizes, bufferSizes) &&
      other.defaultBufferSize == defaultBufferSize &&
      other.outputLatency == outputLatency &&
      other.inputLatency == inputLatency;

  @override
  int get hashCode => Object.hash(
    name,
    hostName,
    Object.hashAll(inputChannelNames),
    Object.hashAll(outputChannelNames),
    Object.hashAll(sampleRates),
    Object.hashAll(bufferSizes),
    defaultBufferSize,
    outputLatency,
    inputLatency,
  );

  @override
  String toString() =>
      'AudioDeviceDescriptor($name on $hostName, '
      '${outputChannelNames.length}out/${inputChannelNames.length}in)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
