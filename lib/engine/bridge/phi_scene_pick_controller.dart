import 'package:flutter/services.dart';
import 'package:macbear_3d/macbear_3d.dart' as m3;
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:vector_math/vector_math_64.dart' as vm64;

import '../../domain/scene/pick_ray.dart';
import 'scene_pick_handler.dart';
import 'scene_unproject.dart';

/// macbear input controller that adds pointer picking and grab to the Scene,
/// delegating to the built-in orbit controller for everything else.
///
/// On a left-button press it unprojects the pointer into a world-space
/// [PickRay] (via [SceneUnproject], reading the live [camera]'s view /
/// projection matrices) and asks the [handler] which agent sits under it:
///   - **hit** → select and grab that agent; a drag then unprojects onto the
///     plane through the agent's grab-start position facing the camera and
///     feeds `moveGrabTo`, and the release hands motion back to the field;
///   - **miss** → clear the selection and hand the gesture to the orbit
///     [fallback], so orbit / pan still work on empty space.
///
/// Right-button presses, the scroll wheel, and the keyboard always go to the
/// [fallback], so pan / zoom / fly navigation are untouched.
///
/// The screen→world math can't run without a live GL context, so this class
/// stays a thin adapter: all the testable geometry lives in [SceneUnproject].
class PhiScenePickController extends m3.M3InputController {
  PhiScenePickController({
    required this.camera,
    required this.handler,
    required this.fallback,
    required this.viewportSize,
  });

  /// The live scene camera, read each gesture for its view / projection
  /// matrices. Shared with [fallback], which mutates it on orbit / pan / zoom.
  final m3.M3Camera camera;

  /// Where picks and grabs are routed — the surface's bridge to the field.
  final ScenePickHandler handler;

  /// The built-in orbit controller, used verbatim for misses, right-drag pan,
  /// scroll zoom, and keyboard navigation.
  final m3.M3CameraOrbitController fallback;

  /// The live viewport size in *logical* pixels — the same units the pointer
  /// position arrives in — as `(width, height)`. Read each gesture so a resize
  /// is picked up. Injected so the geometry can be exercised headless, without
  /// the GL-backed app-engine singleton.
  final (double, double) Function() viewportSize;

  /// Whether a pointer grab is currently in flight. While `true`, moves drag
  /// the grabbed agent instead of orbiting.
  bool _grabbing = false;

  /// The plane a drag is projected onto while grabbing: the point is the
  /// agent's position at grab-start, the normal is the camera's view
  /// direction, so the drag reads as screen-space motion at a stable depth.
  vm64.Vector3 _grabPlanePoint = vm64.Vector3.zero();

  @override
  void onTouchDown(m3.M3Touch touch) {
    // Only the left button picks / grabs; the right button always pans.
    if (touch.buttons == 1) {
      final ray = _rayThrough(touch);
      final key = handler.pick(ray);
      if (key != null) {
        final position = handler.agentPosition(key);
        if (position != null) {
          _grabbing = true;
          _grabPlanePoint = position;
          handler.select(key);
          handler.grab(key);
          return;
        }
      }
      // Left-click on empty space clears the selection, then orbits.
      handler.select(null);
    }
    fallback.onTouchDown(touch);
  }

  @override
  void onTouchMove(m3.M3Touch touch) {
    if (_grabbing) {
      final ray = _rayThrough(touch);
      final target = SceneUnproject.pointOnPlane(
        ray,
        _grabPlanePoint,
        _cameraForward(),
      );
      handler.moveGrabTo(target);
      return;
    }
    fallback.onTouchMove(touch);
  }

  @override
  void onTouchUp(m3.M3Touch touch) {
    if (_grabbing) {
      _grabbing = false;
      handler.releaseGrab();
      return;
    }
    fallback.onTouchUp(touch);
  }

  @override
  void onScroll(double scrollDelta) => fallback.onScroll(scrollDelta);

  @override
  void onKeyDown(KeyDownEvent e) => fallback.onKeyDown(e);

  @override
  void onKeyUp(KeyUpEvent e) => fallback.onKeyUp(e);

  @override
  void onKeyRepeat(PhysicalKeyboardKey key) => fallback.onKeyRepeat(key);

  @override
  void update(double dt) => fallback.update(dt);

  /// Build a world-space ray through the pointer's current position, using the
  /// live camera matrices and the logical viewport size.
  PickRay _rayThrough(m3.M3Touch touch) {
    final (width, height) = viewportSize();
    return SceneUnproject.rayThrough(
      viewProjection: _viewProjection(),
      width: width,
      height: height,
      x: touch.x,
      y: touch.y,
    );
  }

  vm64.Matrix4 _viewProjection() {
    final vp = camera.projectionMatrix.multiplied(camera.viewMatrix);
    return _toVm64Matrix(vp);
  }

  vm64.Vector3 _cameraForward() {
    final forward = (camera.target - camera.position)..normalize();
    return vm64.Vector3(forward.x, forward.y, forward.z);
  }

  static vm64.Matrix4 _toVm64Matrix(vm32.Matrix4 m) =>
      vm64.Matrix4.fromList(m.storage.map((e) => e.toDouble()).toList());
}
