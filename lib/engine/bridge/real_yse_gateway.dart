import 'dart:async';
import 'dart:io';

import 'package:yse/yse.dart';

import '../../domain/project/app_settings/speaker_layout.dart';
import 'audio_device_descriptor.dart';
import 'audio_device_exception.dart';
import 'audio_device_state.dart';
import 'yse_gateway.dart';

/// Production [YseGateway] that forwards every call to `System.instance`.
///
/// Requires `libyse.dll` discoverable at runtime — either next to the
/// executable or pointed at by the `YSE_DLL_PATH` environment variable. See
/// README.md for the Windows setup.
class RealYseGateway implements YseGateway {
  System? _sys;
  final List<MidiIn> _midiInputs = [];
  final List<StreamSubscription<MidiInParsedMessage>> _midiSubs = [];
  final StreamController<void> _midiActivity =
      StreamController<void>.broadcast();
  final Map<int, Channel> _channels = {};
  int _nextChannelId = 1;

  System get _system => _sys ??= System.instance;

  @override
  void init() {
    _system.init();
    _openMidiInputs();
  }

  @override
  void initOffline() {
    _system.initOffline();
    _openMidiInputs();
  }

  @override
  void close() {
    _closeMidiInputs();
    _destroyAllChannels();
    _system.close();
  }

  @override
  String get engineVersion => System.version;

  @override
  String? get libraryPath {
    final path = Platform.environment['YSE_DLL_PATH'];
    return (path != null && path.isNotEmpty) ? path : null;
  }

  @override
  void startUpdateTimer([
    Duration interval = const Duration(milliseconds: 16),
  ]) {
    _system.startUpdateTimer(interval);
  }

  @override
  double get cpuLoad => _system.cpuLoad;

  @override
  int get missedCallbacks => _system.missedCallbacks;

  @override
  set audioTest(bool on) => _system.audioTest = on;

  @override
  double get masterVolume => Channel.master.volume;

  @override
  set masterVolume(double value) => Channel.master.volume = value;

  @override
  double get masterPeak => Channel.master.peakLinearPost();

  @override
  double get activeSampleRate => _system.activeSampleRate;

  @override
  int get activeBufferSize => _system.activeBufferSize;

  @override
  int get activeOutputLatency => _system.activeOutputLatency;

  @override
  List<AudioDeviceDescriptor> audioDevices() => [
    for (final device in _system.devices)
      AudioDeviceDescriptor(
        name: device.name,
        hostName: device.hostName,
        inputChannelNames: device.inputChannelNames,
        outputChannelNames: device.outputChannelNames,
        sampleRates: device.sampleRates,
        bufferSizes: device.bufferSizes,
        defaultBufferSize: device.defaultBufferSize,
        outputLatency: device.outputLatency,
        inputLatency: device.inputLatency,
      ),
  ];

  @override
  void openAudioDevice(
    AudioDeviceDescriptor? descriptor, {
    double? rate,
    int? buffer,
    SpeakerLayout layout = SpeakerLayout.auto,
  }) {
    // Resolve the target against the *current* device list by name + host, so a
    // stored choice follows the hardware across a replug/reindex (design §3).
    // A null descriptor means the platform default.
    final device = descriptor == null
        ? _defaultDevice()
        : _findDevice(descriptor.name, descriptor.hostName);
    if (device == null) {
      throw AudioDeviceException(
        descriptor == null
            ? 'no platform-default audio device is available'
            : 'no audio device named "${descriptor.name}" on '
                  '"${descriptor.hostName}" is available',
      );
    }
    final setup = DeviceSetup()..output = device;
    if (rate != null) setup.sampleRate = rate;
    if (buffer != null) setup.bufferSize = buffer;
    try {
      _system.closeCurrentDevice();
      _system.openDevice(setup, layout: _channelType(layout));
    } on YseException catch (e) {
      // Keep the FFI exception type inside the bridge (project boundary): the
      // caller only ever sees the bridge-level failure.
      throw AudioDeviceException(
        'engine failed to open "${device.name}" on "${device.hostName}": '
        '${e.message}',
      );
    } finally {
      setup.dispose();
    }
  }

  @override
  AudioDeviceState activeAudioState() => AudioDeviceState(
    sampleRate: _system.activeSampleRate,
    bufferSize: _system.activeBufferSize,
    outputLatency: _system.activeOutputLatency,
  );

  @override
  void setAutoReconnect({required bool on, int delayMs = 1000}) =>
      _system.setAutoReconnect(on: on, delayMs: delayMs);

  /// The engine [Device] matching [name] + [hostName] in the current device
  /// list, or `null` when none does (unplugged, renamed).
  Device? _findDevice(String name, String hostName) {
    for (final device in _system.devices) {
      if (device.name == name && device.hostName == hostName) return device;
    }
    return null;
  }

  /// The platform-default output device, resolved by the engine's reported
  /// default name + host, or `null` when it can't be found.
  Device? _defaultDevice() =>
      _findDevice(_system.defaultDevice, _system.defaultHost);

  /// Maps the domain-owned [SpeakerLayout] to yse's `ChannelType`. The mapping
  /// stays here in the bridge so the domain never imports `package:yse`
  /// (design §7).
  ChannelType _channelType(SpeakerLayout layout) => switch (layout) {
    SpeakerLayout.auto => ChannelType.auto,
    SpeakerLayout.mono => ChannelType.mono,
    SpeakerLayout.stereo => ChannelType.stereo,
    SpeakerLayout.quad => ChannelType.quad,
    SpeakerLayout.surround51 => ChannelType.surround51,
    SpeakerLayout.surround51Side => ChannelType.surround51Side,
    SpeakerLayout.surround61 => ChannelType.surround61,
    SpeakerLayout.surround71 => ChannelType.surround71,
  };

  @override
  Stream<void> get midiActivity => _midiActivity.stream;

  @override
  int createChannel(String name) {
    final id = _nextChannelId++;
    _channels[id] = Channel.create(name, parent: Channel.master);
    return id;
  }

  @override
  void destroyChannel(int channelId) {
    final ch = _channels.remove(channelId);
    ch?.dispose();
  }

  @override
  double channelVolume(int channelId) => _channels[channelId]?.volume ?? 0;

  @override
  void setChannelVolume(int channelId, double value) {
    final ch = _channels[channelId];
    if (ch != null) ch.volume = value;
  }

  @override
  double channelPeak(int channelId) =>
      _channels[channelId]?.peakLinearPost() ?? 0;

  void _destroyAllChannels() {
    for (final ch in _channels.values) {
      ch.dispose();
    }
    _channels.clear();
  }

  /// Opens every visible MIDI input and pipes parsed messages into the
  /// shared activity stream. Bottom status only needs an "any activity"
  /// pulse, so individual ports aren't tracked separately yet.
  void _openMidiInputs() {
    for (var i = 0; i < _system.midiInDeviceCount; i++) {
      try {
        final input = MidiIn.open(i);
        _midiInputs.add(input);
        _midiSubs.add(
          input.parsedMessages.listen((_) => _midiActivity.add(null)),
        );
      } on YseException {
        // Some ports may be claimed by other applications — skip them.
      }
    }
  }

  void _closeMidiInputs() {
    for (final sub in _midiSubs) {
      sub.cancel();
    }
    _midiSubs.clear();
    for (final input in _midiInputs) {
      input.dispose();
    }
    _midiInputs.clear();
  }
}
