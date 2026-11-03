import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/flutter_scene_space.dart';
import 'package:vector_math/vector_math_64.dart';

/// The Phi ↔ `flutter_scene` mapping: pure math, no GPU needed.
void main() {
  const viewport = Size(800, 600);
  final camera = Camera(position: Vector3(6, 6, 4), target: Vector3.zero());

  test('engine points swap Y and Z, and back', () {
    final p = Vector3(1, 2, 3);
    final e = FlutterSceneSpace.toEngine(p);
    expect([e.x, e.y, e.z], [1, 3, 2]);
    expect(FlutterSceneSpace.fromEngine(e), p);
  });

  test('the camera target lands in the middle of the viewport', () {
    final centre = FlutterSceneSpace.project(camera, Vector3.zero(), viewport)!;
    expect(centre.dx, closeTo(400, 1e-6));
    expect(centre.dy, closeTo(300, 1e-6));
  });

  test('the picture is right-handed with +Z up (not mirrored)', () {
    // From (6, 6, 4), screen-right is (-1, 1, 0): +Y right, +X left, +Z up.
    final centre = FlutterSceneSpace.project(camera, Vector3.zero(), viewport)!;
    final x = FlutterSceneSpace.project(camera, Vector3(3, 0, 0), viewport)!;
    final y = FlutterSceneSpace.project(camera, Vector3(0, 3, 0), viewport)!;
    final z = FlutterSceneSpace.project(camera, Vector3(0, 0, 3), viewport)!;
    expect(x.dx, lessThan(centre.dx));
    expect(y.dx, greaterThan(centre.dx));
    expect(z.dy, lessThan(centre.dy));
    expect(z.dx, closeTo(centre.dx, 1e-6));
  });

  test('a point behind the camera has no projection', () {
    expect(
      FlutterSceneSpace.project(camera, Vector3(12, 12, 8), viewport),
      isNull,
    );
  });

  test('the pick ray through a projected point passes through it', () {
    for (final point in [
      Vector3.zero(),
      Vector3(3, 0, 0),
      Vector3(0, -3, 1.5),
      Vector3(-2, 4, -1),
    ]) {
      final at = FlutterSceneSpace.project(camera, point, viewport)!;
      final ray = FlutterSceneSpace.rayThrough(camera, at, viewport);
      // Distance from the point to the ray's line.
      final toPoint = point - ray.origin;
      final along = toPoint.dot(ray.direction);
      expect(along, greaterThan(0), reason: 'the ray points into the scene');
      final miss = (toPoint - ray.direction * along).length;
      expect(miss, lessThan(1e-6), reason: 'ray through $point at $at');
    }
  });

  test('the pick ray leaves from in front of the eye toward the scene', () {
    final ray = FlutterSceneSpace.rayThrough(
      camera,
      const Offset(400, 300),
      viewport,
    );
    final forward = (camera.target - camera.position)..normalize();
    expect(ray.direction.dot(forward), closeTo(1, 1e-9));
    expect((ray.origin - camera.position).dot(forward), greaterThan(0));
  });
}
