import 'package:yse/yse.dart';

import 'midi_gateway.dart';

/// Production [MidiGateway] backed by `package:yse`.
///
/// Device enumeration goes through `System.instance` (the same singleton
/// [RealYseGateway] initialises); output goes through a single [MidiOut]
/// port opened on demand. Requires `libyse.dll` discoverable at runtime —
/// see README.md for the Windows setup.
class RealMidiGateway implements MidiGateway {
  System? _sys;
  MidiOut? _out;
  int? _openPort;

  System get _system => _sys ??= System.instance;

  @override
  int get outputDeviceCount => _system.midiOutDeviceCount;

  @override
  String outputDeviceName(int id) => _system.midiOutDeviceName(id);

  @override
  bool get isOpen => _out != null;

  @override
  void open(int port) {
    if (port < 0 || port >= outputDeviceCount) return;
    if (_openPort == port && _out != null) return;
    _disposeOut();
    _out = MidiOut.open(port);
    _openPort = port;
  }

  @override
  void noteOn({
    required int channel,
    required int pitch,
    required int velocity,
  }) => _out?.noteOn(channel: channel, pitch: pitch, velocity: velocity);

  @override
  void noteOff({required int channel, required int pitch}) =>
      _out?.noteOff(channel: channel, pitch: pitch);

  @override
  void raw3(int a, int b, int c) => _out?.raw3(a, b, c);

  @override
  void allNotesOff({int? channel}) => _out?.allNotesOff(channel: channel);

  @override
  void close() => _disposeOut();

  void _disposeOut() {
    _out?.dispose();
    _out = null;
    _openPort = null;
  }
}
