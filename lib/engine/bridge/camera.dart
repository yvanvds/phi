import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Camera state passed from the Scene surface to its renderer.
///
/// Renderer-agnostic — `SceneSurface` computes this from gestures and the
/// concrete `SceneRenderer` derives view/projection matrices.
class Camera {
  Camera({
    required this.position,
    required this.target,
    this.fovYRadians = _defaultFovY,
  });

  /// Eye position in scene space.
  final Vector3 position;

  /// Look-at target in scene space.
  final Vector3 target;

  /// Vertical field of view, in radians.
  final double fovYRadians;

  /// Default 60° vertical FOV.
  static const double _defaultFovY = math.pi / 3;
}
