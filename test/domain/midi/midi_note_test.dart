import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';

void main() {
  group('MidiNote', () {
    test('pitch is a fractional MIDI number (issue #36)', () {
      const n = MidiNote(pitch: 60.5, start: 0, duration: 1, velocity: 0.7);
      expect(n.pitch, 60.5);
      expect(n.pitch, isA<double>());
    });

    test('a whole-number pitch behaves like the old int pitch', () {
      const n = MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1);
      expect(n.pitch, 60);
      expect(n.pitch, 60.0);
    });

    test('copyWith replaces the fractional pitch, keeps the rest', () {
      const n = MidiNote(
        pitch: 60,
        start: 0.5,
        duration: 0.25,
        velocity: 0.4,
        channel: 3,
      );
      final bent = n.copyWith(pitch: 60.25);
      expect(bent.pitch, 60.25);
      expect(bent.start, 0.5);
      expect(bent.duration, 0.25);
      expect(bent.velocity, 0.4);
      expect(bent.channel, 3);
    });

    test('equality and hashCode distinguish fractional pitches', () {
      const a = MidiNote(pitch: 60.25, start: 0, duration: 1, velocity: 1);
      const b = MidiNote(pitch: 60.25, start: 0, duration: 1, velocity: 1);
      const c = MidiNote(pitch: 60.75, start: 0, duration: 1, velocity: 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
