import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('PickRay', () {
    test('normalizes its direction', () {
      final ray = PickRay(origin: Vector3.zero(), direction: Vector3(0, 0, 5));
      expect(ray.direction.length, closeTo(1.0, 1e-12));
      expect(ray.direction, Vector3(0, 0, 1));
    });

    test('clones its inputs so later mutation cannot perturb it', () {
      final origin = Vector3(1, 2, 3);
      final direction = Vector3(1, 0, 0);
      final ray = PickRay(origin: origin, direction: direction);

      origin.setValues(9, 9, 9);
      direction.setValues(0, 1, 0);

      expect(ray.origin, Vector3(1, 2, 3));
      expect(ray.direction, Vector3(1, 0, 0));
    });

    test('hits a sphere dead ahead at the entry distance', () {
      // Ray from origin down +X; unit sphere centred at x=10.
      final ray = PickRay(origin: Vector3.zero(), direction: Vector3(1, 0, 0));
      final t = ray.hitSphere(Vector3(10, 0, 0), 1);
      expect(t, isNotNull);
      expect(t, closeTo(9.0, 1e-12)); // surface is one unit before the centre
    });

    test('misses a sphere off to the side', () {
      final ray = PickRay(origin: Vector3.zero(), direction: Vector3(1, 0, 0));
      // Centre 5 units off the ray's axis, radius 1 — well clear.
      expect(ray.hitSphere(Vector3(10, 5, 0), 1), isNull);
    });

    test('misses a sphere entirely behind the origin', () {
      final ray = PickRay(origin: Vector3.zero(), direction: Vector3(1, 0, 0));
      // Sphere sits at x=-10, radius 1 — the ray points away from it.
      expect(ray.hitSphere(Vector3(-10, 0, 0), 1), isNull);
    });

    test('a ray grazing the far side of a straddling sphere still hits', () {
      // Origin just outside at x=0, sphere centre x=1 radius 2 spans x∈[-1,3].
      // Origin is inside, so distance is 0.
      final ray = PickRay(origin: Vector3.zero(), direction: Vector3(1, 0, 0));
      expect(ray.hitSphere(Vector3(1, 0, 0), 2), 0.0);
    });

    test('an origin inside the sphere is a zero-distance hit', () {
      final ray = PickRay(origin: Vector3.zero(), direction: Vector3(1, 0, 0));
      expect(ray.hitSphere(Vector3.zero(), 1), 0.0);
    });

    test('a tangent ray touches at a single point', () {
      // Ray along +X at y=1; unit sphere at (0,0,0) — grazes at the top.
      final ray = PickRay(
        origin: Vector3(-5, 1, 0),
        direction: Vector3(1, 0, 0),
      );
      final t = ray.hitSphere(Vector3.zero(), 1);
      expect(t, isNotNull);
      expect(t, closeTo(5.0, 1e-9)); // touches at x=0, five units along
    });
  });
}
