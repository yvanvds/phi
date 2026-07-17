import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/transforms/velocity_curve.dart';
import 'package:phi/domain/midi/transforms/velocity_curve_shape.dart';

void main() {
  group('VelocityCurve', () {
    test('identity maps velocity straight through onto [0, 1]', () {
      const curve = VelocityCurve.identity();
      expect(curve.shape, VelocityCurveShape.linear);
      expect(curve.valueAt(0), 0);
      expect(curve.valueAt(0.5), 0.5);
      expect(curve.valueAt(1), 1);
    });

    test('linear scales onto the output range', () {
      const curve = VelocityCurve(valueAt0: 200, valueAt1: 8200);
      expect(curve.valueAt(0), 200);
      expect(curve.valueAt(0.5), 4200);
      expect(curve.valueAt(1), 8200);
    });

    test('an inverted range maps louder onto a lower value', () {
      const curve = VelocityCurve(valueAt0: 100, valueAt1: 0);
      expect(curve.valueAt(0), 100);
      expect(curve.valueAt(1), 0);
      expect(curve.valueAt(0.5), 50);
    });

    test('endpoints are exact for every shape', () {
      for (final shape in VelocityCurveShape.values) {
        final curve = VelocityCurve(shape: shape, valueAt0: 3, valueAt1: 9);
        expect(curve.valueAt(0), 3, reason: '${shape.label} at 0');
        expect(curve.valueAt(1), 9, reason: '${shape.label} at 1');
      }
    });

    test('exponential eases in — the midpoint sits below linear', () {
      const curve = VelocityCurve(
        shape: VelocityCurveShape.exponential,
        valueAt0: 0,
        valueAt1: 100,
      );
      // 0.5² * 100 = 25, below the linear 50.
      expect(curve.valueAt(0.5), 25);
    });

    test('logarithmic eases out — the midpoint sits above linear', () {
      const curve = VelocityCurve(
        shape: VelocityCurveShape.logarithmic,
        valueAt0: 0,
        valueAt1: 100,
      );
      // 1 - (1 - 0.5)² = 0.75 → 75, above the linear 50.
      expect(curve.valueAt(0.5), 75);
    });

    test('stepped quantises onto evenly spaced levels', () {
      const curve = VelocityCurve(
        shape: VelocityCurveShape.stepped,
        valueAt0: 0,
        valueAt1: 1,
        steps: 4,
      );
      // Levels {0, 1/3, 2/3, 1}; the input snaps to the nearest.
      expect(curve.valueAt(0), 0);
      expect(curve.valueAt(0.1), 0);
      expect(curve.valueAt(1), 1);
      expect(curve.valueAt(0.5), closeTo(2 / 3, 1e-9)); // round(1.5) = 2
    });

    test('stepped with a single level collapses to the low end', () {
      const curve = VelocityCurve(
        shape: VelocityCurveShape.stepped,
        valueAt0: 5,
        valueAt1: 9,
        steps: 1,
      );
      expect(curve.valueAt(0), 5);
      expect(curve.valueAt(1), 5);
    });

    test('velocity outside [0, 1] is clamped before shaping', () {
      const curve = VelocityCurve(valueAt0: 0, valueAt1: 10);
      expect(curve.valueAt(-2), 0);
      expect(curve.valueAt(5), 10);
    });

    test('copyWith replaces only the named fields', () {
      const base = VelocityCurve.identity();
      final next = base.copyWith(
        shape: VelocityCurveShape.stepped,
        valueAt1: 42,
      );
      expect(next.shape, VelocityCurveShape.stepped);
      expect(next.valueAt0, base.valueAt0);
      expect(next.valueAt1, 42);
      expect(next.steps, base.steps);
    });

    test('value equality and hashCode', () {
      const a = VelocityCurve(valueAt0: 1, valueAt1: 2);
      const b = VelocityCurve(valueAt0: 1, valueAt1: 2);
      const c = VelocityCurve(valueAt0: 1, valueAt1: 3);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
