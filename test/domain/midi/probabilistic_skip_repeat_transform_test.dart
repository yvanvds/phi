import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/probabilistic_skip_repeat_transform.dart';

MidiNote _n(double pitch, double start, {double duration = 0.25}) =>
    MidiNote(pitch: pitch, start: start, duration: duration, velocity: 0.7);

void main() {
  group('ProbabilisticSkipRepeatTransform', () {
    test('probability 0 for both is the identity', () {
      const t = ProbabilisticSkipRepeatTransform(label: 'off', seed: 1);
      final input = [_n(60, 0), _n(62, 1), _n(64, 2)];
      expect(t.apply(input), input);
    });

    test('skip probability 1 drops every note', () {
      const t = ProbabilisticSkipRepeatTransform(
        label: 'all skip',
        skipProbability: 1,
        seed: 1,
      );
      expect(t.apply([_n(60, 0), _n(62, 1)]), isEmpty);
    });

    test('repeat probability 1 appends N echoes at multiples of duration', () {
      const t = ProbabilisticSkipRepeatTransform(
        label: 'roll',
        repeatProbability: 1,
        repeatCount: 2,
        seed: 1,
      );
      final out = t.apply([_n(60, 0.0, duration: 0.25)]);
      // Original + 2 echoes at 0.25 and 0.50.
      expect(out.map((n) => n.start), [0.0, 0.25, 0.5]);
      expect(out.every((n) => n.pitch == 60), isTrue);
    });

    test('a skipped note is never repeated', () {
      // Skip always fires, so even with repeat=1 the output is empty.
      const t = ProbabilisticSkipRepeatTransform(
        label: 'skip wins',
        skipProbability: 1,
        repeatProbability: 1,
        repeatCount: 3,
        seed: 1,
      );
      expect(t.apply([_n(60, 0)]), isEmpty);
    });

    test('same seed and input produce identical output (reproducible)', () {
      const t = ProbabilisticSkipRepeatTransform(
        label: 'r',
        skipProbability: 0.4,
        repeatProbability: 0.4,
        repeatCount: 2,
        seed: 123,
      );
      final input = List.generate(
        20,
        (i) => _n((60 + i).toDouble(), i.toDouble()),
      );
      expect(t.apply(input), t.apply(input));
    });

    test('a different seed generally produces a different result', () {
      final input = List.generate(
        20,
        (i) => _n((60 + i).toDouble(), i.toDouble()),
      );
      const a = ProbabilisticSkipRepeatTransform(
        label: 'a',
        skipProbability: 0.5,
        repeatProbability: 0.5,
        repeatCount: 2,
        seed: 1,
      );
      const b = ProbabilisticSkipRepeatTransform(
        label: 'b',
        skipProbability: 0.5,
        repeatProbability: 0.5,
        repeatCount: 2,
        seed: 999,
      );
      expect(a.apply(input), isNot(b.apply(input)));
    });

    test('repeatCount below 1 still yields a single echo', () {
      const t = ProbabilisticSkipRepeatTransform(
        label: 'clamp',
        repeatProbability: 1,
        repeatCount: 0,
        seed: 1,
      );
      final out = t.apply([_n(60, 0.0, duration: 0.25)]);
      expect(out.map((n) => n.start), [0.0, 0.25]);
    });

    test('echoes copy pitch, duration, and velocity', () {
      const t = ProbabilisticSkipRepeatTransform(
        label: 'roll',
        repeatProbability: 1,
        repeatCount: 1,
        seed: 1,
      );
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 0,
          duration: 0.5,
          velocity: 0.42,
          voice: 'voice.a',
        ),
      ]);
      expect(out.length, 2);
      expect(out[1].pitch, 64);
      expect(out[1].duration, 0.5);
      expect(out[1].velocity, 0.42);
      expect(out[1].voice, 'voice.a');
      expect(out[1].start, 0.5);
    });

    test('copyWith flips active without losing params', () {
      const t = ProbabilisticSkipRepeatTransform(
        label: 'p',
        skipProbability: 0.3,
        repeatProbability: 0.2,
        repeatCount: 4,
        seed: 8,
      );
      final flipped = t.copyWith(active: false);
      expect(flipped.skipProbability, 0.3);
      expect(flipped.repeatProbability, 0.2);
      expect(flipped.repeatCount, 4);
      expect(flipped.seed, 8);
      expect(flipped.label, 'p');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = ProbabilisticSkipRepeatTransform(label: 'p', seed: 1);
      expect(t.apply(const []), isEmpty);
    });
  });
}
