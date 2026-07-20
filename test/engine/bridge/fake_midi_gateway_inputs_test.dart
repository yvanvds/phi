import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/midi_input_event.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// The fake's MIDI-input surface — enumeration, open/close of named ports, and
/// the activity tick — is what the settings window's input checklist is driven
/// against without hardware.
void main() {
  late FakeMidiGateway gateway;

  setUp(() => gateway = FakeMidiGateway());
  tearDown(() => gateway.dispose());

  test('enumerates the fabricated input ports by name', () {
    expect(gateway.inputDeviceCount, 2);
    expect(gateway.inputDeviceName(0), 'Fake MIDI In');
    expect(gateway.inputDeviceNames(), ['Fake MIDI In', 'Keystation 61']);
  });

  test('openInputs opens exactly the known requested ports', () {
    gateway.openInputs(['Keystation 61']);
    expect(gateway.openInputNames, ['Keystation 61']);
    expect(gateway.calls, contains('openInputs:Keystation 61'));
  });

  test('openInputs skips a name that resolves to no port', () {
    gateway.openInputs(['Keystation 61', 'Not Plugged In']);
    expect(gateway.openInputNames, ['Keystation 61']);
  });

  test('a later openInputs closes ports dropped from the set', () {
    gateway.openInputs(['Fake MIDI In', 'Keystation 61']);
    expect(gateway.openInputNames, ['Fake MIDI In', 'Keystation 61']);

    gateway.openInputs(['Fake MIDI In']);
    expect(gateway.openInputNames, ['Fake MIDI In']);
  });

  test('closeInputs closes every open port', () {
    gateway.openInputs(['Fake MIDI In']);
    gateway.closeInputs();
    expect(gateway.openInputNames, isEmpty);
    expect(gateway.calls, contains('closeInputs'));
  });

  test('inputActivity emits the port name on a synthetic tick', () async {
    final ticks = <String>[];
    final sub = gateway.inputActivity.listen(ticks.add);
    addTearDown(sub.cancel);

    gateway.emitInputActivity('Keystation 61');
    await Future<void>.delayed(Duration.zero);

    expect(ticks, ['Keystation 61']);
  });

  test('inputEvents flows parsed note-on/off events (design §7)', () async {
    final events = <MidiInputEvent>[];
    final sub = gateway.inputEvents.listen(events.add);
    addTearDown(sub.cancel);

    gateway.emitNoteOn('Keystation 61', 60, 100, channel: 3);
    gateway.emitNoteOff('Keystation 61', 60, channel: 3);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first.type, MidiInputEventType.noteOn);
    expect(events.first.note, 60);
    expect(events.first.velocity, 100);
    expect(events.first.channel, 3);
    expect(events.first.port, 'Keystation 61');
    expect(events.last.type, MidiInputEventType.noteOff);
  });

  test('emitInputEvent also ticks activity for the event port', () async {
    final ticks = <String>[];
    final sub = gateway.inputActivity.listen(ticks.add);
    addTearDown(sub.cancel);

    gateway.emitNoteOn('Fake MIDI In', 64, 80);
    await Future<void>.delayed(Duration.zero);

    expect(ticks, ['Fake MIDI In']);
  });
}
