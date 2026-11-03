import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart';

import '../../domain/scene/pick_ray.dart';
import 'scene_orbit_camera.dart';
import 'scene_pick_handler.dart';
import 'scene_unproject.dart';

/// Turns the Scene viewport's raw pointer stream into picks, grabs and
/// camera moves.
///
/// - **Left press on an agent** (the [handler] picks one under the pointer's
///   ray): select and grab it. A drag then pulls it across the plane through
///   its grab-start position facing the camera, so it moves as screen-space
///   motion at a stable depth, and the release hands it back to the field.
/// - **Left press on empty space**: clear the selection, then the drag orbits
///   the [camera].
/// - **Right or middle press**: the drag pans the camera.
/// - **Scroll**: zoom.
///
/// Renderer-agnostic: it reaches the 3D engine only through [rayThrough], so it
/// runs headless in unit tests with any ray function.
class ScenePointerController {
  ScenePointerController({required this.camera, required this.rayThrough});

  /// The orbit camera that misses, right-drags and scrolls move.
  final SceneOrbitCamera camera;

  /// The scene-space ray through a pointer at the given logical position in a
  /// viewport of the given logical size, for the current [camera].
  final PickRay Function(Offset position, Size viewport) rayThrough;

  /// Where picks and grabs go. `null` until the Scene surface installs one
  /// (`SceneRenderer.installPicking`); until then a left press just orbits.
  ScenePickHandler? handler;

  /// Mouse buttons, as `PointerEvent.buttons` bit flags.
  static const int primaryButton = 0x01;
  static const int secondaryButton = 0x02;
  static const int middleButton = 0x04;

  _Gesture _gesture = _Gesture.none;
  int? _pointer;
  Vector3 _grabPlanePoint = Vector3.zero();

  /// Whether a pointer grab is in flight.
  bool get grabbing => _gesture == _Gesture.grab;

  /// A pointer went down at [position] with [buttons] held. Starts a grab,
  /// an orbit or a pan; a second pointer while one gesture runs is ignored.
  void pointerDown(int pointer, Offset position, int buttons, Size viewport) {
    if (_gesture != _Gesture.none) return;
    if (buttons & primaryButton != 0) {
      final handler = this.handler;
      if (handler != null) {
        final key = handler.pick(rayThrough(position, viewport));
        final grabbed = key == null ? null : handler.agentPosition(key);
        if (key != null && grabbed != null) {
          _grabPlanePoint = grabbed;
          handler
            ..select(key)
            ..grab(key);
          _start(pointer, _Gesture.grab);
          return;
        }
        handler.select(null);
      }
      _start(pointer, _Gesture.orbit);
    } else if (buttons & (secondaryButton | middleButton) != 0) {
      _start(pointer, _Gesture.pan);
    }
  }

  /// The pointer moved by [delta] to [position]. Returns whether the camera
  /// moved, so the caller knows to redraw.
  bool pointerMove(int pointer, Offset position, Offset delta, Size viewport) {
    if (pointer != _pointer) return false;
    switch (_gesture) {
      case _Gesture.grab:
        final target = SceneUnproject.pointOnPlane(
          rayThrough(position, viewport),
          _grabPlanePoint,
          camera.forward,
        );
        handler?.moveGrabTo(target);
        return false;
      case _Gesture.orbit:
        camera.orbit(delta.dx, delta.dy);
        return true;
      case _Gesture.pan:
        camera.pan(delta.dx, delta.dy, viewport.height);
        return true;
      case _Gesture.none:
        return false;
    }
  }

  /// The pointer lifted: a grab releases its agent back to the field.
  void pointerUp(int pointer) {
    if (pointer != _pointer) return;
    if (_gesture == _Gesture.grab) handler?.releaseGrab();
    _gesture = _Gesture.none;
    _pointer = null;
  }

  /// The pointer was cancelled (focus lost, window gone): end it like a lift,
  /// so a grab never stays stuck on.
  void pointerCancel(int pointer) => pointerUp(pointer);

  /// End whatever gesture is in flight — the view went away mid-drag.
  void cancelAll() {
    final pointer = _pointer;
    if (pointer != null) pointerUp(pointer);
  }

  /// A scroll of [scrollDelta] logical pixels (positive = down = zoom out).
  /// Returns whether the camera moved.
  bool scroll(double scrollDelta) {
    if (scrollDelta == 0) return false;
    camera.zoom(scrollDelta);
    return true;
  }

  void _start(int pointer, _Gesture gesture) {
    _pointer = pointer;
    _gesture = gesture;
  }
}

enum _Gesture { none, grab, orbit, pan }
