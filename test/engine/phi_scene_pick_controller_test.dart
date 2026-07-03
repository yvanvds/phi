import 'package:flutter_test/flutter_test.dart';
import 'package:macbear_3d/macbear_3d.dart' as m3;
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/engine/bridge/phi_scene_pick_controller.dart';
import 'package:phi/engine/bridge/scene_pick_handler.dart';
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:vector_math/vector_math_64.dart' as vm64;

/// Records every call so a test can assert what the pointer drove, standing in
/// for the Scene surface's real bridge to the field.
class _FakeHandler implements ScenePickHandler {
  _FakeHandler({this.pickResult, vm64.Vector3? position})
    : position = position ?? vm64.Vector3.zero();

  int? pickResult;
  vm64.Vector3 position;

  final List<PickRay> picks = [];
  final List<int?> selections = [];
  int? grabbed;
  vm64.Vector3? movedTo;
  bool released = false;

  @override
  int? pick(PickRay ray) {
    picks.add(ray);
    return pickResult;
  }

  @override
  vm64.Vector3? agentPosition(int key) => position.clone();

  @override
  void grab(int key) => grabbed = key;

  @override
  void moveGrabTo(vm64.Vector3 target) => movedTo = target;

  @override
  void releaseGrab() => released = true;

  @override
  void select(int? key) => selections.add(key);
}

void main() {
  // A camera five units up +Z looking at the origin, +Y up, 800×600 viewport —
  // so the centre pixel shoots down the view axis onto an agent at the origin.
  m3.M3Camera buildCamera() {
    final camera = m3.M3Camera();
    camera.setViewport(0, 0, 800, 600, fovy: 60);
    camera.setLookat(
      vm32.Vector3(0, 0, 5),
      vm32.Vector3.zero(),
      vm32.Vector3(0, 1, 0),
    );
    return camera;
  }

  PhiScenePickController buildController(
    m3.M3Camera camera,
    _FakeHandler handler,
  ) => PhiScenePickController(
    camera: camera,
    handler: handler,
    fallback: m3.M3CameraOrbitController(camera),
    viewportSize: () => (800.0, 600.0),
  );

  m3.M3Touch touchAt(double x, double y, {int buttons = 1}) =>
      m3.M3Touch(1)..touchDown(m3.M3TouchPoint(vm32.Vector2(x, y), buttons, 0));

  group('PhiScenePickController — pick + grab', () {
    test('a left-press over an agent selects and grabs it', () {
      final handler = _FakeHandler(pickResult: 42);
      final controller = buildController(buildCamera(), handler);

      controller.onTouchDown(touchAt(400, 300));

      expect(handler.picks, hasLength(1));
      expect(handler.selections, [42]);
      expect(handler.grabbed, 42);
    });

    test('a drag after a grab pulls toward the pointer at the grab depth', () {
      final handler = _FakeHandler(pickResult: 42); // agent at the origin
      final controller = buildController(buildCamera(), handler);

      controller.onTouchDown(touchAt(400, 300));

      // Drag the pointer up the screen; the target must ride the z = 0 plane
      // (through the grabbed agent, facing the camera) and move toward +Y.
      final move = touchAt(400, 300)
        ..touchMove(m3.M3TouchPoint(vm32.Vector2(400, 200), 1, 0.1));
      controller.onTouchMove(move);

      expect(handler.movedTo, isNotNull);
      expect(handler.movedTo!.z, closeTo(0, 1e-6));
      expect(handler.movedTo!.y, greaterThan(0));
    });

    test('the release hands motion back to the field', () {
      final handler = _FakeHandler(pickResult: 42);
      final controller = buildController(buildCamera(), handler);

      controller.onTouchDown(touchAt(400, 300));
      controller.onTouchUp(touchAt(400, 300));

      expect(handler.released, isTrue);
    });
  });

  group('PhiScenePickController — misses and non-grab gestures', () {
    test('a left-press on empty space clears the selection, never grabs', () {
      final handler = _FakeHandler(pickResult: null); // ray hits nothing
      final controller = buildController(buildCamera(), handler);

      controller.onTouchDown(touchAt(400, 300));

      expect(handler.picks, hasLength(1));
      expect(handler.selections, [null]);
      expect(handler.grabbed, isNull);
    });

    test('a right-press never picks — it goes straight to orbit/pan', () {
      final handler = _FakeHandler(pickResult: 42);
      final controller = buildController(buildCamera(), handler);

      controller.onTouchDown(touchAt(400, 300, buttons: 2));

      expect(handler.picks, isEmpty);
      expect(handler.grabbed, isNull);
      expect(handler.selections, isEmpty);
    });
  });
}
