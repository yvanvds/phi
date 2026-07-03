import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// A ray in scene space — an [origin] and a normalized [direction].
///
/// The pure geometry the Scene's picking runs on: turning "the performer
/// pointed here" into "which agent is under the cursor" is a ray/sphere
/// hit-test against the live agent set (see [SceneField.pick]).
///
/// Deliberately camera-free. The screen→ray unprojection needs the live
/// camera's view/projection matrices and belongs with the Scene surface when
/// it graduates from its stub; this type sits below that so *code* can build a
/// ray and pick an agent without any viewport at all — anything the mouse can
/// do, code can do.
class PickRay {
  /// Builds a ray from [origin] along [direction]. The direction is stored
  /// normalized, so [hitSphere] returns a distance in scene units regardless
  /// of the caller's vector length. Both inputs are cloned, so a later mutation
  /// of the caller's vectors can't perturb the ray.
  PickRay({required Vector3 origin, required Vector3 direction})
    : origin = origin.clone(),
      direction = direction.normalized();

  /// The point the ray starts from, in scene space.
  final Vector3 origin;

  /// Unit direction the ray travels along.
  final Vector3 direction;

  /// Distance along the ray to the nearest intersection with the sphere at
  /// [center] with [radius], or `null` when the ray misses (or the sphere sits
  /// entirely behind the [origin]).
  ///
  /// When the origin lies *inside* the sphere the ray is already touching it,
  /// so the hit distance is `0` — an agent you are inside is as close as it
  /// gets. Used to rank candidates in [SceneField.pick]: the smallest returned
  /// distance is the agent under the cursor.
  double? hitSphere(Vector3 center, double radius) {
    final m = origin - center;
    final b = m.dot(direction);
    final c = m.dot(m) - radius * radius;
    // Ray starts outside (c > 0) and points away from the sphere (b > 0):
    // it can never reach it.
    if (c > 0 && b > 0) return null;
    final discriminant = b * b - c;
    if (discriminant < 0) return null; // no real intersection — a miss
    final root = math.sqrt(discriminant);
    final tNear = -b - root;
    if (tNear >= 0) return tNear; // entry point ahead of the origin
    // tNear is behind the origin: either the origin is inside the sphere
    // (hit distance 0) or the whole sphere is behind it (a miss).
    final tFar = -b + root;
    return tFar >= 0 ? 0.0 : null;
  }
}
