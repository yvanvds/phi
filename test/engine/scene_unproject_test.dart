import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/engine/bridge/scene_unproject.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  // A camera five units up the +Z axis, looking at the origin, +Y up — the
  // same look-at the Scene surface seeds. Aspect 4:3.
  Matrix4 viewProjectionFor({
    Vector3? eye,
    double width = 800,
    double height = 600,
  }) {
    final view = makeViewMatrix(
      eye ?? Vector3(0, 0, 5),
      Vector3.zero(),
      Vector3(0, 1, 0),
    );
    final projection = makePerspectiveMatrix(
      radians(60),
      width / height,
      0.1,
      100,
    );
    return projection.multiplied(view);
  }

  group('rayThrough', () {
    test('the centre pixel shoots straight down the view axis', () {
      final ray = SceneUnproject.rayThrough(
        viewProjection: viewProjectionFor(),
        width: 800,
        height: 600,
        x: 400,
        y: 300,
      );
      // Eye at +Z looking at the origin → the axis points down -Z.
      expect(ray.direction.x, closeTo(0, 1e-9));
      expect(ray.direction.y, closeTo(0, 1e-9));
      expect(ray.direction.z, closeTo(-1, 1e-9));
      // Origin sits on the near plane, just in front of the eye.
      expect(ray.origin.z, closeTo(4.9, 1e-6));
    });

    test('a pixel right of centre tilts the ray toward +X', () {
      final ray = SceneUnproject.rayThrough(
        viewProjection: viewProjectionFor(),
        width: 800,
        height: 600,
        x: 600, // right half
        y: 300,
      );
      expect(ray.direction.x, greaterThan(0));
      expect(ray.direction.z, lessThan(0));
    });

    test(
      'a pixel below centre tilts the ray toward -Y (screen y grows down)',
      () {
        final ray = SceneUnproject.rayThrough(
          viewProjection: viewProjectionFor(),
          width: 800,
          height: 600,
          x: 400,
          y: 450, // lower half of the screen
        );
        expect(ray.direction.y, lessThan(0));
      },
    );

    test('the ray actually strikes an agent under the centre pixel', () {
      // With the camera on +Z looking at the origin, a sphere at the origin
      // sits under the centre pixel.
      final ray = SceneUnproject.rayThrough(
        viewProjection: viewProjectionFor(),
        width: 800,
        height: 600,
        x: 400,
        y: 300,
      );
      expect(ray.hitSphere(Vector3.zero(), 0.55), isNotNull);
    });
  });

  group('pointOnPlane', () {
    test('meets a plane through the origin facing the camera', () {
      final ray = PickRay(
        origin: Vector3(0, 0, 5),
        direction: Vector3(0, 0, -1),
      );
      final hit = SceneUnproject.pointOnPlane(
        ray,
        Vector3.zero(),
        Vector3(0, 0, 1),
      );
      expect(hit.x, closeTo(0, 1e-12));
      expect(hit.y, closeTo(0, 1e-12));
      expect(hit.z, closeTo(0, 1e-12));
    });

    test('holds the target at the plane depth as the ray tilts', () {
      // Ray from +Z angled toward +X; plane z=0 facing the camera. The hit
      // must land on z=0 with a positive x.
      final ray = PickRay(
        origin: Vector3(0, 0, 5),
        direction: Vector3(1, 0, -1),
      );
      final hit = SceneUnproject.pointOnPlane(
        ray,
        Vector3.zero(),
        Vector3(0, 0, 1),
      );
      expect(hit.z, closeTo(0, 1e-12));
      expect(hit.x, closeTo(5, 1e-9));
    });

    test('falls back to the plane point when the ray is parallel', () {
      final ray = PickRay(
        origin: Vector3(0, 3, 0),
        direction: Vector3(1, 0, 0),
      );
      final planePoint = Vector3(2, 0, 0);
      final hit = SceneUnproject.pointOnPlane(
        ray,
        planePoint,
        Vector3(0, 1, 0), // ray runs in the plane → parallel
      );
      expect(hit, planePoint);
    });
  });
}
