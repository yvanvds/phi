import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/humanization_transform.dart';

MidiNote _n(double start, {double velocity = 0.5}) =>
    MidiNote(pitch: 60, start: start, duration: 0.25, velocity: velocity);

void main() {
  group('HumanizationTransform', () {
    test('same seed and input produce identical output (reproducible)', () {
      const t = HumanizationTransform(
        label: 'human',
        timeRange: 0.05,
        velocityRange: 0.2,
        seed: 42,
      );
      final input = [_n(0.5), _n(1.0), _n(1.5)];
      expect(t.apply(input), t.apply(input));
    });

    test('a different seed generally produces different jitter', () {
      final input = [_n(0.5), _n(1.0), _n(1.5)];
      const a = HumanizationTransform(
        label: 'a',
        timeRange: 0.05,
        velocityRange: 0.2,
        seed: 1,
      );
      const b = HumanizationTransform(
        label: 'b',
        timeRange: 0.05,
        velocityRange: 0.2,
        seed: 2,
      );
      expect(a.apply(input), isNot(b.apply(input)));
    });

    test('jitter stays within the configured range', () {
      const range = 0.05;
      const vRange = 0.2;
      const t = HumanizationTransform(
        label: 'human',
        timeRange: range,
        velocityRange: vRange,
        seed: 7,
      );
      final input = List.generate(50, (i) => _n(i.toDouble(), velocity: 0.5));
      final out = t.apply(input);
      for (var i = 0; i < input.length; i++) {
        expect((out[i].start - input[i].start).abs(), lessThanOrEqualTo(range));
        expect(
          (out[i].velocity - input[i].velocity).abs(),
          lessThanOrEqualTo(vRange + 1e-9),
        );
      }
    });

    test('velocity is clamped to [0, 1]', () {
      const t = HumanizationTransform(
        label: 'human',
        timeRange: 0,
        velocityRange: 1.0,
        seed: 3,
      );
      final out = t.apply([
        for (var i = 0; i < 40; i++) _n(i.toDouble(), velocity: 0.98),
        for (var i = 0; i < 40; i++) _n(i.toDouble(), velocity: 0.02),
      ]);
      for (final n in out) {
        expect(n.velocity, inInclusiveRange(0.0, 1.0));
      }
    });

    test('start never goes negative', () {
      const t = HumanizationTransform(
        label: 'human',
        timeRange: 0.5,
        velocityRange: 0,
        seed: 9,
      );
      final out = t.apply([for (var i = 0; i < 40; i++) _n(0.0)]);
      for (final n in out) {
        expect(n.start, greaterThanOrEqualTo(0.0));
      }
    });

    test('zero ranges leave notes unchanged but still consume the stream', () {
      const t = HumanizationTransform(
        label: 'human',
        timeRange: 0,
        velocityRange: 0,
        seed: 5,
      );
      final input = [_n(0.5, velocity: 0.4), _n(1.0, velocity: 0.6)];
      expect(t.apply(input), input);
    });

    test('preserves pitch, duration, and channel', () {
      const t = HumanizationTransform(label: 'human', seed: 1);
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 1,
          duration: 0.75,
          velocity: 0.5,
          channel: 3,
        ),
      ]);
      expect(out.single.pitch, 64);
      expect(out.single.duration, 0.75);
      expect(out.single.channel, 3);
    });

    test('copyWith flips active without losing params', () {
      const t = HumanizationTransform(
        label: 'h',
        timeRange: 0.03,
        velocityRange: 0.15,
        seed: 11,
      );
      final flipped = t.copyWith(active: false);
      expect(flipped.timeRange, 0.03);
      expect(flipped.velocityRange, 0.15);
      expect(flipped.seed, 11);
      expect(flipped.label, 'h');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = HumanizationTransform(label: 'h', seed: 1);
      expect(t.apply(const []), isEmpty);
    });
  });
}
