import 'dart:async';

import 'package:yse/yse.dart';

import 'midi_gateway.dart';
import 'midi_input_event.dart';
import 'midi_transport.dart';
import 'real_midi_transport.dart';

/// Production [MidiGateway] backed by `package:yse`.
///
/// Device enumeration goes through `System.instance` (the same singleton
/// [RealYseGateway] initialises); output goes through a single [MidiOut]
/// port opened on demand. Timed note dispatch has moved to the engine clip
/// transport ([createTransport]) since issue #101; what stays here is device
/// enumeration, the output port, [allNotesOff], and — since issue #150 — the
/// MIDI **input** surface: name-addressed enumeration, open/close of the enabled
/// input ports (each mapped to a live [MidiIn]), and an [inputActivity] tick per
/// received message. Nothing routes MIDI-in anywhere yet (design §8); this only
/// opens the hardware and reports activity. Requires `libyse.dll` discoverable
/// at runtime — see README.md for the Windows setup.
class RealMidiGateway implements MidiGateway {
  System? _sys;
  MidiOut? _out;
  int? _openPort;

  /// Open input ports keyed by device name, and their message subscriptions —
  /// kept in step so [closeInputs] / [openInputs] can dispose exactly the ports
  /// they own. Insertion-ordered so [openInputNames] reports open order.
  final Map<String, MidiIn> _inputs = {};
  final Map<String, StreamSubscription<MidiInParsedMessage>> _inputSubs = {};
  final StreamController<String> _inputActivity =
      StreamController<String>.broadcast();
  final StreamController<MidiInputEvent> _inputEvents =
      StreamController<MidiInputEvent>.broadcast();

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
  int get inputDeviceCount => _system.midiInDeviceCount;

  @override
  String inputDeviceName(int id) => _system.midiInDeviceName(id);

  @override
  List<String> inputDeviceNames() => [
    for (var i = 0; i < _system.midiInDeviceCount; i++)
      _system.midiInDeviceName(i),
  ];

  @override
  List<String> get openInputNames => List<String>.unmodifiable(_inputs.keys);

  @override
  Stream<String> get inputActivity => _inputActivity.stream;

  @override
  Stream<MidiInputEvent> get inputEvents => _inputEvents.stream;

  @override
  void openInputs(List<String> names) {
    final desired = names.toSet();
    // Close ports no longer wanted.
    for (final name in _inputs.keys.toList()) {
      if (!desired.contains(name)) _closeInput(name);
    }
    // Open newly wanted ports, resolving each name to a current index.
    for (final name in names) {
      if (_inputs.containsKey(name)) continue;
      final index = _indexOfInput(name);
      if (index == null) continue; // no visible port by that name — skip.
      try {
        final input = MidiIn.open(index);
        _inputs[name] = input;
        _inputSubs[name] = input.parsedMessages.listen(
          (message) => _onParsedInput(name, message),
        );
      } on YseException {
        // Port claimed by another application — leave it unopened.
      }
    }
  }

  @override
  void closeInputs() {
    for (final name in _inputs.keys.toList()) {
      _closeInput(name);
    }
  }

  /// The current input-device index reporting [name], or `null` when none does.
  int? _indexOfInput(String name) {
    for (var i = 0; i < _system.midiInDeviceCount; i++) {
      if (_system.midiInDeviceName(i) == name) return i;
    }
    return null;
  }

  void _closeInput(String name) {
    _inputSubs.remove(name)?.cancel();
    _inputs.remove(name)?.dispose();
  }

  /// Fan one received message out to both input streams: the unchanged
  /// activity tick (design §6) and, when it is a note message, the parsed note
  /// event (design §7). One subscription drives both so a port is read once.
  void _onParsedInput(String name, MidiInParsedMessage message) {
    _inputActivity.add(name);
    final event = MidiInputEvent.fromParsed(
      status: message.status,
      wireChannel: message.channel,
      data1: message.data1,
      data2: message.data2,
      port: name,
      timestamp: message.timestamp,
    );
    if (event != null) _inputEvents.add(event);
  }

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
  void sendNoteOn({
    required int channel,
    required int note,
    required int velocity,
  }) => _out?.noteOn(channel: channel, pitch: note, velocity: velocity);

  @override
  void sendNoteOff({required int channel, required int note}) =>
      _out?.noteOff(channel: channel, pitch: note);

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
