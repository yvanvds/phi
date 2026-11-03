import 'dart:async';

import 'package:yse/yse.dart';

/// Every MIDI message that arrives on one input port, in order, as byte
/// values (issue #509). `MidiLoopback.capture` opens one on the loopback's
/// input, so a test reads back what a patch's `.midiout` sent.
///
/// Messages arrive on RtMidi's thread and are posted to this isolate's event
/// loop, so a test must yield (an awaited delay) before they show up in
/// [messages].
final class MidiCapture {
  /// Starts collecting from [_port], which this capture now owns.
  MidiCapture(this._port) {
    _sub = _port.rawMessages.listen((m) => messages.add(m.bytes.toList()));
  }

  final MidiIn _port;
  late final StreamSubscription<MidiInRawMessage> _sub;

  /// What has arrived so far, oldest first.
  final List<List<int>> messages = [];

  /// Forgets what has arrived so far.
  void clear() => messages.clear();

  /// Stops collecting and closes the port.
  Future<void> close() async {
    await _sub.cancel();
    _port.dispose();
  }
}
