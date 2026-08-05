import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';

/// The cable cubic's control points moved onto the **vertical** axis with the
/// ports (issue #377): a wire leaves an outlet heading down out of its box's
/// bottom edge and arrives at an inlet from above the next box's top edge.
void main() {
  // An outlet on one box's bottom edge, an inlet on the next box's top edge,
  // directly below it — the ordinary Max-style stack.
  const a = Offset(100, 100);
  const b = Offset(160, 260);

  test('the wire leaves the outlet downward, not sideways', () {
    final justOut = PatchCableGeometry.pointAt(a, b, 0.02);

    expect(justOut.dy, greaterThan(a.dy));
    // Barely any sideways travel yet: the tangent at the outlet is vertical.
    expect((justOut.dx - a.dx).abs(), lessThan((justOut.dy - a.dy).abs()));
  });

  test('the wire arrives at the inlet from above', () {
    final justIn = PatchCableGeometry.pointAt(a, b, 0.98);

    expect(justIn.dy, lessThan(b.dy));
    expect((justIn.dx - b.dx).abs(), lessThan((justIn.dy - b.dy).abs()));
  });

  test('endpoints are exact', () {
    expect(PatchCableGeometry.pointAt(a, b, 0), a);
    expect(PatchCableGeometry.pointAt(a, b, 1), b);
  });

  test('a cable running straight down stays on its own vertical line', () {
    const straightBelow = Offset(100, 300);
    for (final t in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      expect(PatchCableGeometry.pointAt(a, straightBelow, t).dx, a.dx);
    }
  });

  test('distanceTo is ~0 on the curve and large off it', () {
    final mid = PatchCableGeometry.pointAt(a, b, 0.5);

    expect(PatchCableGeometry.distanceTo(a, b, mid), lessThan(1));
    expect(
      PatchCableGeometry.distanceTo(a, b, mid + const Offset(200, 0)),
      greaterThan(PatchCanvasConstants.cableHitThreshold),
    );
  });
}
