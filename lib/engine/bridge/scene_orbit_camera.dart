import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';

/// The Scene viewport's orbit camera, in Phi's scene space (+Z up).
///
/// Holds the camera as a look-at [target] plus spherical coordinates around
/// it — [yaw] about +Z, [pitch] above the XY plane, and a [distance] — so the
/// pointer's orbit / pan / zoom are each one small, testable operation. Pure
/// `vector_math_64`, no 3D-engine types: the renderer reads [camera] each frame
/// and derives its own view / projection from it.
class SceneOrbitCamera {
  /// An orbit camera framing [initial] — see [reset].
  SceneOrbitCamera(Camera initial) {
    reset(initial);
  }

  /// Radians of yaw / pitch per logical pixel of orbit drag.
  static const double orbitRadiansPerPixel = 0.008;

  /// How far a scroll notch zooms: the distance scales by
  /// `exp(scrollDelta * zoomPerScrollUnit)`.
  static const double zoomPerScrollUnit = 0.0015;

  /// Closest the camera may come to its target, in scene units.
  static const double minDistance = 0.5;

  /// Farthest the camera may pull back from its target, in scene units.
  static const double maxDistance = 200.0;

  /// Pitch stays this far short of straight up / down, so the view never
  /// looks along the up axis (where a look-at basis degenerates).
  static const double _pitchMargin = 0.02;
  static const double _maxPitch = math.pi / 2 - _pitchMargin;

  Vector3 _target = Vector3.zero();
  double _distance = 1;
  double _yaw = 0;
  double _pitch = 0;
  double _fovYRadians = math.pi / 3;

  /// The point the camera looks at and orbits around.
  Vector3 get target => _target.clone();

  /// Distance from the eye to [target].
  double get distance => _distance;

  /// Azimuth of the eye around [target], about +Z, from +X toward +Y.
  double get yaw => _yaw;

  /// Elevation of the eye above the XY plane through [target].
  double get pitch => _pitch;

  /// Vertical field of view, in radians.
  double get fovYRadians => _fovYRadians;

  /// The eye position.
  Vector3 get position {
    final c = math.cos(_pitch);
    return _target +
        Vector3(
          c * math.cos(_yaw) * _distance,
          c * math.sin(_yaw) * _distance,
          math.sin(_pitch) * _distance,
        );
  }

  /// Unit view direction, from the eye toward [target].
  Vector3 get forward => (_target - position)..normalize();

  /// Unit screen-right direction in scene space.
  Vector3 get right => forward.cross(Vector3(0, 0, 1))..normalize();

  /// Unit screen-up direction in scene space.
  Vector3 get up => right.cross(forward)..normalize();

  /// The current pose as a renderer-agnostic [Camera].
  Camera get camera =>
      Camera(position: position, target: target, fovYRadians: _fovYRadians);

  /// Adopt [camera]'s pose: its target, and the eye's distance, yaw and pitch
  /// around it (pitch clamped short of the poles). A camera sitting on its own
  /// target keeps the current distance.
  void reset(Camera camera) {
    _target = camera.target.clone();
    _fovYRadians = camera.fovYRadians;
    final offset = camera.position - camera.target;
    final length = offset.length;
    if (length < 1e-9) return;
    _distance = length.clamp(minDistance, maxDistance);
    _yaw = math.atan2(offset.y, offset.x);
    _pitch = math.asin((offset.z / length).clamp(-1.0, 1.0));
    _pitch = _pitch.clamp(-_maxPitch, _maxPitch);
  }

  /// Orbit by a pointer drag of ([dx], [dy]) logical pixels: dragging right
  /// swings the eye the other way so the scene turns with the pointer, and
  /// dragging down raises the eye to look from above.
  void orbit(double dx, double dy) {
    _yaw -= dx * orbitRadiansPerPixel;
    _pitch = (_pitch + dy * orbitRadiansPerPixel).clamp(-_maxPitch, _maxPitch);
  }

  /// Pan by a pointer drag of ([dx], [dy]) logical pixels in a viewport
  /// [viewportHeight] pixels tall: the target slides in the view plane so the
  /// scene at the target's depth follows the pointer.
  void pan(double dx, double dy, double viewportHeight) {
    if (viewportHeight <= 0) return;
    final unitsPerPixel =
        2 * _distance * math.tan(_fovYRadians / 2) / viewportHeight;
    _target =
        _target - right * (dx * unitsPerPixel) + up * (dy * unitsPerPixel);
  }

  /// Zoom by a scroll of [scrollDelta] (positive = scroll down = pull back),
  /// clamped to [minDistance]..[maxDistance].
  void zoom(double scrollDelta) {
    _distance = (_distance * math.exp(scrollDelta * zoomPerScrollUnit)).clamp(
      minDistance,
      maxDistance,
    );
  }
}
