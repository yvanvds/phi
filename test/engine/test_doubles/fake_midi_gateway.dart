import 'dart:async';

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

  /// The transport minted by the **most recent** [createTransport], or `null`
  /// before the first call. Tests read its recorded events to assert the pushed
  /// note sequence. For concurrent playback (issue #187) use [transports], which
  /// keeps every minted transport (one per playing session).
  FakeMidiTransport? transport;

  /// Every transport minted by [createTransport], in creation order — one per
  /// session that has played. Lets a test observe concurrent sessions running on
  /// their own clocks side by side, not just the last one.
  final List<FakeMidiTransport> transports = [];

  /// Names returned by [outputDeviceName], indexed by port. Defaults to a
  /// single fake port so [open] succeeds out of the box.
  List<String> deviceNames = const ['Fake MIDI Out'];

  /// Fabricated input-port names, so the settings window's input checklist is
  /// drivable without hardware. Reassign to model other (or no) inputs.
  List<String> inputNames = const ['Fake MIDI In', 'Keystation 61'];

  int? openPort;

  final List<String> _openInputs = [];
  final StreamController<String> _inputActivity =
      StreamController<String>.broadcast();

  @override
  int get outputDeviceCount => deviceNames.length;

  @override
  String outputDeviceName(int id) => deviceNames[id];

  @override
  int get inputDeviceCount => inputNames.length;

  @override
  String inputDeviceName(int id) => inputNames[id];

  @override
  List<String> inputDeviceNames() => List<String>.of(inputNames);

  @override
  List<String> get openInputNames => List<String>.unmodifiable(_openInputs);

  @override
  Stream<String> get inputActivity => _inputActivity.stream;

  @override
  void openInputs(List<String> names) {
    calls.add('openInputs:${names.join(',')}');
    // Open exactly the requested names that resolve to a known port; an unknown
    // name is skipped, mirroring the real gateway's name→index resolution.
    _openInputs
      ..clear()
      ..addAll(names.where(inputNames.contains));
  }

  @override
  void closeInputs() {
    calls.add('closeInputs');
    _openInputs.clear();
  }

  /// Push a synthetic activity tick for [portName] — drives [inputActivity]
  /// listeners as if that open port had delivered a MIDI message.
  void emitInputActivity(String portName) => _inputActivity.add(portName);

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
    final minted = FakeMidiTransport(clockName: clockName, tempo: tempo);
    transports.add(minted);
    return transport = minted;
  }

  @override
  void allNotesOff({int? channel}) =>
      calls.add('allNotesOff:${channel ?? 'all'}');

  @override
  void close() {
    calls.add('close');
    openPort = null;
  }

  /// Close the input-activity stream controller. Call from test teardown to keep
  /// `flutter test` from leaking a pending broadcast controller.
  Future<void> dispose() => _inputActivity.close();
}
