import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/quantization_transform.dart';

MidiNote _n(double start, {double duration = 0.25, double velocity = 0.7}) =>
    MidiNote(pitch: 60, start: start, duration: duration, velocity: velocity);

void main() {
  group('QuantizationTransform', () {
    test('gravity 0 is the identity', () {
      const t = QuantizationTransform(gravity: 0, label: 'off');
      final input = [_n(0.13), _n(0.61)];
      expect(t.apply(input), input);
    });

    test('gravity 1 snaps hard to the nearest grid line', () {
      const t = QuantizationTransform(gravity: 1, grid: 0.25, label: 'hard');
      // 0.13 → nearest 0.25-cell is 0.25; 0.61 → 0.5; 0.10 → 0.0.
      final out = t.apply([_n(0.13), _n(0.61), _n(0.10)]);
      expect(out.map((n) => n.start), [0.25, 0.5, 0.0]);
    });

    test('partial gravity closes that fraction of the distance', () {
      const t = QuantizationTransform(gravity: 0.6, grid: 0.25, label: 'soft');
      // 0.20 → nearest is 0.25; move 60% of (0.25-0.20)=0.05 → 0.20+0.03=0.23.
      final out = t.apply([_n(0.20)]);
      expect(out.single.start, closeTo(0.23, 1e-9));
    });

    test('leaves duration and velocity untouched', () {
      const t = QuantizationTransform(gravity: 1, grid: 0.25, label: 'hard');
      final out = t.apply([_n(0.13, duration: 0.75, velocity: 0.42)]);
      expect(out.single.duration, 0.75);
      expect(out.single.velocity, 0.42);
    });

    test('a non-positive grid passes notes through unchanged', () {
      const t = QuantizationTransform(gravity: 1, grid: 0, label: 'no grid');
      final input = [_n(0.13)];
      expect(t.apply(input), input);
    });

    test('gravity above 1 clamps to a hard snap', () {
      const t = QuantizationTransform(gravity: 5, grid: 0.25, label: 'over');
      expect(t.apply([_n(0.13)]).single.start, 0.25);
    });

    test('copyWith flips active without losing gravity/grid/label', () {
      const t = QuantizationTransform(gravity: 0.6, grid: 0.5, label: 'q');
      final flipped = t.copyWith(active: false);
      expect(flipped.gravity, 0.6);
      expect(flipped.grid, 0.5);
      expect(flipped.label, 'q');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = QuantizationTransform(gravity: 1, label: 'q');
      expect(t.apply(const []), isEmpty);
    });
  });
}
