import 'package:vector_math/vector_math_64.dart';

import '../../domain/scene/pick_ray.dart';

/// Screen→world unprojection for the Scene surface's pointer picking.
///
/// Pure math over `vector_math_64`, deliberately free of any 3D-engine types
/// so it can be unit-tested headless. The macbear input controller reads the
/// live camera's view/projection matrices, hands them here, and gets back a
/// [PickRay] in scene space (the same ray `SceneField.pick` runs on) plus, for
/// a drag, the world point under the pointer on a chosen plane.
///
/// The pointer coordinates are logical pixels with the origin at the widget's
/// top-left and `y` growing downward (Flutter's `PointerEvent.localPosition`);
/// normalized-device coordinates have `y` growing up, so the mapping flips it.
class SceneUnproject {
  const SceneUnproject._();

  /// A world-space [PickRay] through the pointer at ([x], [y]) logical pixels
  /// inside a [width]×[height] viewport, given the camera's combined
  /// [viewProjection] matrix (`projectionMatrix * viewMatrix`).
  ///
  /// The ray runs from the near plane to the far plane through that pixel, so
  /// its origin sits on the near plane and its direction points into the
  /// scene.
  static PickRay rayThrough({
    required Matrix4 viewProjection,
    required double width,
    required double height,
    required double x,
    required double y,
  }) {
    final invViewProjection = Matrix4.inverted(viewProjection);
    final ndcX = 2.0 * x / width - 1.0;
    final ndcY = 1.0 - 2.0 * y / height;
    final near = _unproject(invViewProjection, ndcX, ndcY, -1.0);
    final far = _unproject(invViewProjection, ndcX, ndcY, 1.0);
    return PickRay(origin: near, direction: far - near);
  }

  /// The point where [ray] meets the plane through [planePoint] with unit
  /// normal [planeNormal].
  ///
  /// Used to turn a drag ray into a single 3D target: the grab holds the agent
  /// on the plane through its grab-start position facing the camera, so the
  /// drag reads as screen-space movement at a stable depth. Falls back to
  /// [planePoint] when the ray runs (near-)parallel to the plane, so a grazing
  /// drag never flings the target off to infinity.
  static Vector3 pointOnPlane(
    PickRay ray,
    Vector3 planePoint,
    Vector3 planeNormal,
  ) {
    final denom = ray.direction.dot(planeNormal);
    if (denom.abs() < 1e-9) return planePoint.clone();
    final t = (planePoint - ray.origin).dot(planeNormal) / denom;
    return ray.origin + ray.direction * t;
  }

  static Vector3 _unproject(
    Matrix4 invViewProjection,
    double ndcX,
    double ndcY,
    double ndcZ,
  ) {
    final v = invViewProjection.transformed(Vector4(ndcX, ndcY, ndcZ, 1.0));
    final invW = 1.0 / v.w;
    return Vector3(v.x * invW, v.y * invW, v.z * invW);
  }
}
