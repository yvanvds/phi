import 'package:phi/engine/bridge/midi_gateway.dart';
import 'package:phi/engine/bridge/midi_transport.dart';

import 'fake_midi_transport.dart';

/// In-memory [MidiGateway] used in unit and widget tests.
///
/// Records the immediate output calls (open / allNotesOff / close) so tests can
/// assert the port lifecycle without touching `package:yse`. Timed note
/// dispatch moved to the transport (issue #101): [createTransport] mints a
/// [FakeMidiTransport], kept on [transport], which records the pushed note
/// list. Mirrors `FakeYseGateway` for the MIDI side.
class FakeMidiGateway implements MidiGateway {
  /// Ordered log of every immediate call, formatted as `verb:args`.
  final List<String> calls = [];

  /// The transport minted by [createTransport], or `null` before the first
  /// call. Tests read its recorded events to assert the pushed note sequence.
  FakeMidiTransport? transport;

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
  MidiTransport createTransport({
    required String clockName,
    required double tempo,
  }) {
    calls.add('createTransport:$clockName');
    return transport = FakeMidiTransport(clockName: clockName, tempo: tempo);
  }

  @override
  void allNotesOff({int? channel}) =>
      calls.add('allNotesOff:${channel ?? 'all'}');

  @override
  void close() {
    calls.add('close');
    openPort = null;
  }
}
