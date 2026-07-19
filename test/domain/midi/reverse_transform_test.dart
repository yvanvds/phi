import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/reverse_transform.dart';

MidiNote _n(double pitch, double start, {double duration = 0.25}) =>
    MidiNote(pitch: pitch, start: start, duration: duration, velocity: 0.7);

void main() {
  group('ReverseTransform', () {
    test('mirrors a single note within the window', () {
      const t = ReverseTransform(lengthBeats: 16, label: 'rev');
      final out = t.apply([_n(60, 0, duration: 2)]);
      // 16 - 0 - 2 = 14.
      expect(out.single.start, 14);
    });

    test('the note that ends last now starts first', () {
      const t = ReverseTransform(lengthBeats: 4, label: 'rev');
      final out = t.apply([_n(60, 0, duration: 1), _n(62, 3, duration: 1)]);
      expect(out[0].start, 3); // was 0..1, now 3..4
      expect(out[1].start, 0); // was 3..4, now 0..1
    });

    test('applying twice restores the original notes', () {
      const t = ReverseTransform(lengthBeats: 16, label: 'rev');
      final input = [_n(60, 0), _n(62, 3.5, duration: 0.75), _n(64, 10)];
      expect(t.apply(t.apply(input)), input);
    });

    test('preserves duration, pitch, velocity, and voice', () {
      const t = ReverseTransform(lengthBeats: 16, label: 'rev');
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 2,
          duration: 0.5,
          velocity: 0.42,
          voice: 'voice.a',
        ),
      ]);
      expect(out.single.duration, 0.5);
      expect(out.single.pitch, 64);
      expect(out.single.velocity, 0.42);
      expect(out.single.voice, 'voice.a');
    });

    test('a non-positive lengthBeats passes notes through unchanged', () {
      final input = [_n(60, 1)];
      expect(
        const ReverseTransform(lengthBeats: 0, label: 'zero').apply(input),
        input,
      );
      expect(
        const ReverseTransform(lengthBeats: -4, label: 'neg').apply(input),
        input,
      );
    });

    test('copyWith flips active without losing lengthBeats/label', () {
      const t = ReverseTransform(lengthBeats: 16, label: 'r');
      final flipped = t.copyWith(active: false);
      expect(flipped.lengthBeats, 16);
      expect(flipped.label, 'r');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = ReverseTransform(lengthBeats: 16, label: 'r');
      expect(t.apply(const []), isEmpty);
    });
  });
}
