import 'package:phi/engine/bridge/midi_gateway.dart';

/// In-memory [MidiGateway] used in unit and widget tests.
///
/// Records every output call against the port so tests can assert the exact
/// note sequence a clip produces without touching `package:yse` or its
/// native library. Mirrors `FakeYseGateway` for the MIDI side.
class FakeMidiGateway implements MidiGateway {
  /// Ordered log of every call, formatted as `verb:args`. The note sequence
  /// for a clip falls out of this list (issue #29's acceptance test).
  final List<String> calls = [];

  /// Names returned by [outputDeviceName], indexed by port. Defaults to a
  /// single fake port so [open] succeeds out of the box.
  List<String> deviceNames = const ['Fake MIDI Out'];

  int? openPort;

  @override
  int get outputDeviceCount => deviceNames.length;

  @override
  String outputDeviceName(int id) => deviceNames[id];

  @override
  bool get isOpen => openPort != null;

  @override
  void open(int port) {
    if (port < 0 || port >= outputDeviceCount) return;
    calls.add('open:$port');
    openPort = port;
  }

  @override
  void noteOn({
    required int channel,
    required int pitch,
    required int velocity,
  }) => calls.add('noteOn:$channel:$pitch:$velocity');

  @override
  void noteOff({required int channel, required int pitch}) =>
      calls.add('noteOff:$channel:$pitch');

  @override
  void raw3(int a, int b, int c) => calls.add('raw3:$a:$b:$c');

  @override
  void allNotesOff({int? channel}) =>
      calls.add('allNotesOff:${channel ?? 'all'}');

  @override
  void close() {
    calls.add('close');
    openPort = null;
  }
}
