import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/state_machine/state_canvas_constants.dart';
import 'package:phi/design/widgets/state_machine/state_transition_geometry.dart';

void main() {
  group('StateTransitionGeometry.curveBetween', () {
    test('endpoints clip onto the facing edges of source and target', () {
      const src = Rect.fromLTWH(0, 0, 100, 50);
      const dst = Rect.fromLTWH(200, 0, 100, 50);

      final curve = StateTransitionGeometry.curveBetween(src, dst);

      // target is to the right of source → arrow leaves source.right,
      // enters target.left.
      expect(curve.a, const Offset(100, 25));
      expect(curve.b, const Offset(200, 25));
    });

    test('target to the left swaps the picked edges so the arrow does not '
        'cross its own source node', () {
      const src = Rect.fromLTWH(200, 0, 100, 50);
      const dst = Rect.fromLTWH(0, 0, 100, 50);

      final curve = StateTransitionGeometry.curveBetween(src, dst);

      expect(curve.a, const Offset(200, 25));
      expect(curve.b, const Offset(100, 25));
    });
  });

  group('StateTransitionGeometry.distanceTo', () {
    test('returns ~0 for a point on the curve start', () {
      const src = Rect.fromLTWH(0, 0, 100, 50);
      const dst = Rect.fromLTWH(200, 0, 100, 50);
      final curve = StateTransitionGeometry.curveBetween(src, dst);

      final d = StateTransitionGeometry.distanceTo(curve, curve.a);

      expect(d, lessThan(0.5));
    });

    test('returns a large distance for a point far from the curve', () {
      const src = Rect.fromLTWH(0, 0, 100, 50);
      const dst = Rect.fromLTWH(200, 0, 100, 50);
      final curve = StateTransitionGeometry.curveBetween(src, dst);

      // A point 200px below the horizontal cubic must be > the
      // hit-threshold away — otherwise the click hit-test would
      // false-positive on empty canvas.
      final d = StateTransitionGeometry.distanceTo(
        curve,
        const Offset(150, 225),
      );

      expect(d, greaterThan(StateCanvasConstants.transitionHitThreshold));
    });
  });
}
