import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/stretch_transform.dart';

void main() {
  group('StretchTransform', () {
    test('doubles start and duration at factor 2', () {
      const t = StretchTransform(factor: 2, label: '2x');
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0.5, duration: 0.25, velocity: 0.7),
        MidiNote(pitch: 62, start: 1.0, duration: 0.5, velocity: 0.6),
      ]);
      expect(out.map((n) => n.start), [1.0, 2.0]);
      expect(out.map((n) => n.duration), [0.5, 1.0]);
    });

    test('compresses at factor 0.5', () {
      const t = StretchTransform(factor: 0.5, label: 'half');
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 1.0, duration: 0.5, velocity: 0.7),
      ]);
      expect(out.single.start, 0.5);
      expect(out.single.duration, 0.25);
    });

    test('leaves pitch, velocity, and channel untouched', () {
      const t = StretchTransform(factor: 2, label: '2x');
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 1,
          duration: 0.5,
          velocity: 0.42,
          channel: 3,
        ),
      ]);
      expect(out.single.pitch, 64);
      expect(out.single.velocity, 0.42);
      expect(out.single.channel, 3);
    });

    test('factor 1 is the identity', () {
      const t = StretchTransform(factor: 1, label: '1x');
      const input = [
        MidiNote(pitch: 60, start: 0.5, duration: 0.25, velocity: 0.7),
      ];
      expect(t.apply(input), input);
    });

    test('a non-positive factor passes notes through unchanged', () {
      const input = [
        MidiNote(pitch: 60, start: 0.5, duration: 0.25, velocity: 0.7),
      ];
      expect(
        const StretchTransform(factor: 0, label: 'zero').apply(input),
        input,
      );
      expect(
        const StretchTransform(factor: -2, label: 'neg').apply(input),
        input,
      );
    });

    test('copyWith flips active without losing factor/label', () {
      const t = StretchTransform(factor: 1.5, label: 's');
      final flipped = t.copyWith(active: false);
      expect(flipped.factor, 1.5);
      expect(flipped.label, 's');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = StretchTransform(factor: 2, label: 's');
      expect(t.apply(const []), isEmpty);
    });
  });
}
