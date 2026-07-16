import 'package:yse/yse.dart';

import 'midi_gateway.dart';
import 'midi_transport.dart';
import 'real_midi_transport.dart';

/// Production [MidiGateway] backed by `package:yse`.
///
/// Device enumeration goes through `System.instance` (the same singleton
/// [RealYseGateway] initialises); output goes through a single [MidiOut]
/// port opened on demand. Timed note dispatch has moved to the engine clip
/// transport ([createTransport]) since issue #101; what stays here is device
/// enumeration, the port, and [allNotesOff]. Requires `libyse.dll`
/// discoverable at runtime — see README.md for the Windows setup.
class RealMidiGateway implements MidiGateway {
  System? _sys;
  MidiOut? _out;
  int? _openPort;

  System get _system => _sys ??= System.instance;

  /// The currently open output port, or `null` when none is open. Exposed so a
  /// [RealMidiTransport] this gateway mints can route the engine clip to the
  /// same port the gateway opened, rather than opening a second device handle.
  MidiOut? get midiOut => _out;

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
  MidiTransport createTransport({
    required String clockName,
    required double tempo,
  }) {
    final clock = DomainClock(clockName, tempo: tempo);
    final clip = ClipTransport(clock);
    return RealMidiTransport(this, clock, clip);
  }

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
