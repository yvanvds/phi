import 'package:yse/yse.dart';

/// A way to play MIDI **into** the engine's MIDI input objects (`.notein`,
/// `.ctlin`, `.midiin` …) without a keyboard (issue #508).
///
/// The engine has no call that injects a message into its MIDI input hub, so
/// a test reaches those objects the way a keyboard does: through a real input
/// port. On Linux the ALSA sequencer's `Midi Through` port is one: whatever
/// is sent to it as an output comes back on it as an input. This opens that
/// port's output and sends raw bytes into it; the patch's MIDI input objects
/// listen on the same port's input.
///
/// Where there is no such port — Windows, or a Linux machine without the
/// `snd-seq-dummy` module, which is the case on CI runners — [open] returns
/// `null`, and a test skips the steps that need a keyboard. libyse's
/// session must be up (`System.instance.init…`) before [open].
final class MidiLoopback {
  MidiLoopback._(this.inputPort, this._out);

  /// The name a loopback port's input and output both contain.
  static const String portName = 'Midi Through';

  /// The input port index the loopback answers on: the `port` argument a
  /// patch's MIDI input objects need to hear [send].
  final int inputPort;

  final MidiOut _out;

  /// Opens the loopback, or returns `null` when the machine has none.
  static MidiLoopback? open() {
    final system = System.instance;
    int find(int count, String Function(int) name) {
      for (var i = 0; i < count; i++) {
        if (name(i).contains(portName)) return i;
      }
      return -1;
    }

    final input = find(system.midiInDeviceCount, system.midiInDeviceName);
    final output = find(system.midiOutDeviceCount, system.midiOutDeviceName);
    if (input < 0 || output < 0) return null;
    return MidiLoopback._(input, MidiOut.open(output));
  }

  /// Sends one MIDI message, as its byte values: `[144, 60, 100]` is a
  /// note-on for middle C on channel 1. It reaches the patch a moment later,
  /// in wall-clock time, and the patch drains it on its next audio block.
  void send(List<int> bytes) => _out.raw(bytes);

  /// Closes the output port.
  void close() => _out.dispose();
}
