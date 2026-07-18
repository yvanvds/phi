import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/app_settings/midi_settings.dart';

void main() {
  group('MidiSettings', () {
    test('defaults to no output port and no inputs', () {
      const midi = MidiSettings();
      expect(midi.outputPort, isNull);
      expect(midi.inputPorts, isEmpty);
    });

    test('round-trips a fully-specified value through JSON', () {
      const midi = MidiSettings(
        outputPort: 'loopMIDI Port',
        inputPorts: ['Keystation 61', 'Launchpad'],
      );
      expect(MidiSettings.fromJson(midi.toJson()), midi);
    });

    test('round-trips the all-default value through JSON', () {
      const midi = MidiSettings();
      expect(MidiSettings.fromJson(midi.toJson()), midi);
    });

    test('omits a null output port but always writes inputPorts', () {
      const midi = MidiSettings(inputPorts: ['A']);
      final json = midi.toJson();
      expect(json.containsKey('outputPort'), isFalse);
      expect(json['inputPorts'], ['A']);
    });

    test('fromJson tolerates missing keys with defaults', () {
      final midi = MidiSettings.fromJson(const {});
      expect(midi, const MidiSettings());
    });

    test('fromJson drops non-string input entries', () {
      final midi = MidiSettings.fromJson(const {
        'outputPort': 5,
        'inputPorts': ['ok', 7, null, 'also-ok'],
      });
      expect(midi.outputPort, isNull);
      expect(midi.inputPorts, ['ok', 'also-ok']);
    });

    test('value equality and hashCode by fields', () {
      const a = MidiSettings(outputPort: 'p', inputPorts: ['a']);
      const b = MidiSettings(outputPort: 'p', inputPorts: ['a']);
      const c = MidiSettings(outputPort: 'p', inputPorts: ['b']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('withOutputPort sets and clears the output port', () {
      const midi = MidiSettings(inputPorts: ['A']);
      final set = midi.withOutputPort('loopMIDI');
      expect(set.outputPort, 'loopMIDI');
      expect(set.inputPorts, ['A']); // inputs untouched
      final cleared = set.withOutputPort(null);
      expect(cleared.outputPort, isNull);
      expect(cleared.inputPorts, ['A']);
    });

    test('withInput enables (appends, de-duplicated) and disables', () {
      const midi = MidiSettings(outputPort: 'p', inputPorts: ['A']);
      final added = midi.withInput('B', enabled: true);
      expect(added.inputPorts, ['A', 'B']);
      expect(added.outputPort, 'p'); // output untouched

      // Enabling an already-enabled port is a no-op.
      expect(added.withInput('B', enabled: true), added);

      final removed = added.withInput('A', enabled: false);
      expect(removed.inputPorts, ['B']);

      // Disabling a port that isn't enabled is a no-op.
      expect(removed.withInput('Z', enabled: false), removed);
    });
  });
}
