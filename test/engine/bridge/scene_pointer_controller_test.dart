import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/scene_orbit_camera.dart';
import 'package:phi/engine/bridge/scene_pick_handler.dart';
import 'package:phi/engine/bridge/scene_pointer_controller.dart';
import 'package:vector_math/vector_math_64.dart';

/// Records the controller's calls and answers picks from a fixed agent table:
/// an agent is "under" the pointer when the ray's origin x matches its key.
class _Handler implements ScenePickHandler {
  final Map<int, Vector3> agents = {7: Vector3(0, 0, 0)};
  final List<String> calls = [];
  Vector3? lastGrabTarget;

  @override
  int? pick(PickRay ray) {
    calls.add('pick');
    final key = ray.origin.x.round();
    return agents.containsKey(key) ? key : null;
  }

  @override
  Vector3? agentPosition(int key) => agents[key]?.clone();

  @override
  void grab(int key) => calls.add('grab:$key');

  @override
  void moveGrabTo(Vector3 target) {
    calls.add('move');
    lastGrabTarget = target;
  }

  @override
  void releaseGrab() => calls.add('release');

  @override
  void select(int? key) => calls.add('select:$key');
}

void main() {
  const viewport = Size(400, 300);
  late SceneOrbitCamera camera;
  late _Handler handler;
  late ScenePointerController controller;

  setUp(() {
    // Eye on +X looking at the origin: the view plane through the origin is
    // the YZ plane.
    camera = SceneOrbitCamera(
      Camera(position: Vector3(10, 0, 0), target: Vector3.zero()),
    );
    handler = _Handler();
    // A stand-in projection: the ray's origin x carries the pointer's x (so
    // the fake handler can tell hits from misses), its y and z carry the
    // pointer's y, and it points down -X like the camera does.
    controller = ScenePointerController(
      camera: camera,
      rayThrough: (p, _) => PickRay(
        origin: Vector3(p.dx, -p.dy, -p.dy),
        direction: Vector3(-1, 0, 0),
      ),
    )..handler = handler;
  });

  test('a left press on an agent selects and grabs it', () {
    controller.pointerDown(1, const Offset(7, 0), 0x01, viewport);
    expect(handler.calls, ['pick', 'select:7', 'grab:7']);
    expect(controller.grabbing, isTrue);
  });

  test('a grab drag pulls toward the view-plane point; a lift releases', () {
    controller.pointerDown(1, const Offset(7, 0), 0x01, viewport);
    final yaw = camera.yaw;
    final moved = controller.pointerMove(
      1,
      const Offset(7, 20),
      const Offset(0, 20),
      viewport,
    );
    expect(moved, isFalse, reason: 'a grab does not move the camera');
    expect(camera.yaw, yaw);
    // The ray hits the plane x = 0 (through the agent, facing the camera).
    expect(handler.lastGrabTarget!.x, closeTo(0, 1e-9));
    expect(handler.lastGrabTarget!.y, closeTo(-20, 1e-9));
    controller.pointerUp(1);
    expect(handler.calls.last, 'release');
    expect(controller.grabbing, isFalse);
  });

  test('a left press on empty space clears the selection and orbits', () {
    controller.pointerDown(1, const Offset(50, 0), 0x01, viewport);
    expect(handler.calls, ['pick', 'select:null']);
    final yaw = camera.yaw;
    expect(
      controller.pointerMove(
        1,
        const Offset(60, 0),
        const Offset(10, 0),
        viewport,
      ),
      isTrue,
    );
    expect(camera.yaw, isNot(yaw));
    controller.pointerUp(1);
    expect(handler.calls, isNot(contains('release')));
  });

  test('right and middle drags pan', () {
    for (final button in [0x02, 0x04]) {
      final before = camera.target;
      controller.pointerDown(1, const Offset(7, 0), button, viewport);
      expect(handler.calls, isEmpty, reason: 'panning never picks');
      controller.pointerMove(
        1,
        const Offset(17, 0),
        const Offset(10, 0),
        viewport,
      );
      expect(camera.target.distanceTo(before), greaterThan(0));
      controller.pointerUp(1);
    }
  });

  test('scroll zooms', () {
    final distance = camera.distance;
    expect(controller.scroll(0), isFalse);
    expect(controller.scroll(100), isTrue);
    expect(camera.distance, greaterThan(distance));
  });

  test('a second pointer mid-gesture is ignored', () {
    controller.pointerDown(1, const Offset(7, 0), 0x01, viewport);
    controller.pointerDown(2, const Offset(50, 0), 0x01, viewport);
    expect(
      controller.pointerMove(
        2,
        const Offset(60, 0),
        const Offset(10, 0),
        viewport,
      ),
      isFalse,
    );
    controller.pointerUp(2);
    expect(controller.grabbing, isTrue);
  });

  test('cancel and cancelAll release a grab', () {
    controller.pointerDown(1, const Offset(7, 0), 0x01, viewport);
    controller.pointerCancel(1);
    expect(handler.calls.last, 'release');
    controller.pointerDown(3, const Offset(7, 0), 0x01, viewport);
    controller.cancelAll();
    expect(handler.calls.where((c) => c == 'release'), hasLength(2));
    expect(controller.grabbing, isFalse);
  });

  test('without a handler a left press just orbits', () {
    final bare = ScenePointerController(
      camera: camera,
      rayThrough: (_, _) =>
          PickRay(origin: Vector3.zero(), direction: Vector3(1, 0, 0)),
    );
    final yaw = camera.yaw;
    bare.pointerDown(1, Offset.zero, 0x01, viewport);
    bare.pointerMove(1, const Offset(5, 0), const Offset(5, 0), viewport);
    expect(camera.yaw, isNot(yaw));
  });
}
