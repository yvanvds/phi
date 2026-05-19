import 'dart:async';

import 'package:yse/yse.dart';

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
  void close() {
    _closeMidiInputs();
    _destroyAllChannels();
    _system.close();
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
