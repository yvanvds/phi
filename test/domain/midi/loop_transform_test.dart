import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/loop_transform.dart';

MidiNote _n(double pitch, double start, {double duration = 0.25}) =>
    MidiNote(pitch: pitch, start: start, duration: duration, velocity: 0.7);

void main() {
  group('LoopTransform', () {
    test('no repeat knobs set plays the loop once (identity)', () {
      const t = LoopTransform(loopLengthBeats: 4, label: 'once');
      final input = [_n(60, 0), _n(62, 1)];
      expect(t.apply(input), input);
    });

    test('repeatCount tiles the notes at multiples of loopLengthBeats', () {
      const t = LoopTransform(loopLengthBeats: 4, repeatCount: 3, label: 'x3');
      final out = t.apply([_n(60, 0), _n(62, 1)]);
      expect(out.map((n) => n.start), [0, 1, 4, 5, 8, 9]);
      expect(out.every((n) => n.pitch == 60 || n.pitch == 62), isTrue);
    });

    test('repeatCount below 1 still plays once', () {
      const t = LoopTransform(
        loopLengthBeats: 4,
        repeatCount: 0,
        label: 'clamp',
      );
      final out = t.apply([_n(60, 0)]);
      expect(out.map((n) => n.start), [0]);
    });

    test('untilBeat fills the loop and drops the overshooting tail', () {
      const t = LoopTransform(loopLengthBeats: 4, untilBeat: 10, label: 'fill');
      // Loop of [0, 2] tiled at 0, 4, 8 — beat 8's pair is [8, 10], and 10
      // is at the boundary so it's dropped.
      final out = t.apply([_n(60, 0), _n(62, 2)]);
      expect(out.map((n) => n.start), [0, 2, 4, 6, 8]);
    });

    test('untilBeat overrides repeatCount when both are set', () {
      const t = LoopTransform(
        loopLengthBeats: 4,
        repeatCount: 100,
        untilBeat: 8,
        label: 'fill-wins',
      );
      final out = t.apply([_n(60, 0)]);
      expect(out.map((n) => n.start), [0, 4]);
    });

    test('phaseOffset shifts every iteration', () {
      const t = LoopTransform(
        loopLengthBeats: 4,
        repeatCount: 2,
        phaseOffset: 1,
        label: 'phased',
      );
      final out = t.apply([_n(60, 0)]);
      expect(out.map((n) => n.start), [1, 5]);
    });

    test('leaves duration, velocity, pitch, and voice untouched', () {
      const t = LoopTransform(loopLengthBeats: 4, repeatCount: 2, label: 'p');
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 0,
          duration: 0.5,
          velocity: 0.42,
          voice: 'voice.a',
        ),
      ]);
      for (final n in out) {
        expect(n.pitch, 64);
        expect(n.duration, 0.5);
        expect(n.velocity, 0.42);
        expect(n.voice, 'voice.a');
      }
    });

    test('a non-positive loopLengthBeats passes notes through unchanged', () {
      final input = [_n(60, 0)];
      expect(
        const LoopTransform(loopLengthBeats: 0, label: 'zero').apply(input),
        input,
      );
      expect(
        const LoopTransform(loopLengthBeats: -4, label: 'neg').apply(input),
        input,
      );
    });

    test('copyWith flips active without losing params', () {
      const t = LoopTransform(
        loopLengthBeats: 8,
        label: 'l',
        repeatCount: 2,
        untilBeat: 20,
        phaseOffset: 1.5,
      );
      final flipped = t.copyWith(active: false);
      expect(flipped.loopLengthBeats, 8);
      expect(flipped.repeatCount, 2);
      expect(flipped.untilBeat, 20);
      expect(flipped.phaseOffset, 1.5);
      expect(flipped.label, 'l');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = LoopTransform(loopLengthBeats: 4, repeatCount: 2, label: 'l');
      expect(t.apply(const []), isEmpty);
    });
  });
}
