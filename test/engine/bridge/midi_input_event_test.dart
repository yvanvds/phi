import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/midi_input_event.dart';

/// [MidiInputEvent.fromParsed] is the pure decode the real gateway runs on every
/// `MidiInParsedMessage` — testing it here covers the real parsing path without
/// `libyse.dll` (design `docs/design/racks-and-voices.md` §7).
void main() {
  const port = 'Keystation 61';

  MidiInputEvent? decode(int status, int wireChannel, int d1, int d2) =>
      MidiInputEvent.fromParsed(
        status: status,
        wireChannel: wireChannel,
        data1: d1,
        data2: d2,
        port: port,
      );

  test('a note-on (0x90) with velocity decodes to a note-on event', () {
    final event = decode(0x90, 0, 60, 100)!;
    expect(event.type, MidiInputEventType.noteOn);
    expect(event.note, 60);
    expect(event.velocity, 100);
    expect(event.port, port);
  });

  test('the wire channel is reported 1-based (engine voice space, §3)', () {
    // Wire nibble 0 → channel 1; nibble 15 → channel 16.
    expect(decode(0x90, 0, 60, 100)!.channel, 1);
    expect(decode(0x90, 15, 60, 100)!.channel, 16);
  });

  test('a note-on with velocity 0 normalises to a note-off', () {
    final event = decode(0x90, 2, 60, 0)!;
    expect(event.type, MidiInputEventType.noteOff);
    expect(event.note, 60);
    expect(event.channel, 3);
  });

  test('a note-off (0x80) decodes to a note-off event', () {
    final event = decode(0x80, 0, 64, 40)!;
    expect(event.type, MidiInputEventType.noteOff);
    expect(event.note, 64);
    expect(event.velocity, 40);
  });

  test('a non-note message (CC 0xB0, pitch-bend 0xE0) decodes to null', () {
    expect(decode(0xB0, 0, 7, 127), isNull);
    expect(decode(0xE0, 0, 0, 64), isNull);
  });

  test('value equality holds by field', () {
    const a = MidiInputEvent(
      type: MidiInputEventType.noteOn,
      note: 60,
      velocity: 100,
      channel: 1,
      port: port,
    );
    const b = MidiInputEvent(
      type: MidiInputEventType.noteOn,
      note: 60,
      velocity: 100,
      channel: 1,
      port: port,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
