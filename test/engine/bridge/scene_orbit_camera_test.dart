import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/scene_orbit_camera.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  Matcher closeToVector(Vector3 v) =>
      predicate<Vector3>((a) => a.distanceTo(v) < 1e-9, 'within 1e-9 of $v');

  test('round-trips a camera pose', () {
    final camera = Camera(position: Vector3(6, 6, 4), target: Vector3(1, 0, 0));
    final orbit = SceneOrbitCamera(camera);
    expect(orbit.position, closeToVector(camera.position));
    expect(orbit.target, closeToVector(camera.target));
    expect(orbit.distance, closeTo((Vector3(5, 6, 4)).length, 1e-9));
    expect(orbit.camera.fovYRadians, camera.fovYRadians);
  });

  test('the view basis is right-handed with +Z up', () {
    final orbit = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    expect(orbit.forward, closeToVector(Vector3(-1, 0, 0)));
    // Looking down -X with +Z up, screen-right is +Y.
    expect(orbit.right, closeToVector(Vector3(0, 1, 0)));
    expect(orbit.up, closeToVector(Vector3(0, 0, 1)));
  });

  test('orbit swings the eye around the target at a fixed distance', () {
    final orbit = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    orbit.orbit(100, 0);
    expect(
      orbit.yaw,
      closeTo(-100 * SceneOrbitCamera.orbitRadiansPerPixel, 1e-12),
    );
    expect(orbit.distance, closeTo(10, 1e-9));
    expect(orbit.target, closeToVector(Vector3.zero()));
    // Dragging down raises the eye.
    orbit.orbit(0, 50);
    expect(orbit.position.z, greaterThan(0));
  });

  test('pitch stops short of the poles', () {
    final orbit = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    orbit.orbit(0, 1e6);
    expect(orbit.pitch, lessThan(math.pi / 2));
    expect(orbit.right.length, closeTo(1, 1e-9), reason: 'basis stays sound');
    orbit.orbit(0, -2e6);
    expect(orbit.pitch, greaterThan(-math.pi / 2));
  });

  test('pan slides the target in the view plane with the pointer', () {
    final orbit = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    final before = orbit.position;
    orbit.pan(100, 0, 500);
    // Content follows the pointer right, so the target moves screen-left (-Y).
    expect(orbit.target.y, lessThan(0));
    expect(orbit.target.z, closeTo(0, 1e-9));
    expect(orbit.distance, closeTo(10, 1e-9));
    expect(orbit.position - before, closeToVector(orbit.target));
    orbit.pan(0, 100, 500);
    expect(orbit.target.z, greaterThan(0), reason: 'dragging down lifts it');
  });

  test('zoom scales the distance and clamps it', () {
    final orbit = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    orbit.zoom(120);
    expect(orbit.distance, greaterThan(10));
    orbit.zoom(-1e6);
    expect(orbit.distance, SceneOrbitCamera.minDistance);
    orbit.zoom(1e6);
    expect(orbit.distance, SceneOrbitCamera.maxDistance);
  });

  test('reset adopts a new pose; a degenerate one keeps the distance', () {
    final orbit = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    orbit.reset(Camera(position: Vector3(1, 1, 1), target: Vector3(1, 1, 1)));
    expect(orbit.target, closeToVector(Vector3(1, 1, 1)));
    expect(orbit.distance, closeTo(10, 1e-9));
  });
}
