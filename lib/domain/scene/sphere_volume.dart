import 'package:vector_math/vector_math_64.dart';

import 'effect_volume.dart';

/// A spherical [EffectVolume] — every point within [radius] of [center].
///
/// Membership uses the squared distance, so the test stays sqrt-free and an
/// agent exactly [radius] away counts as inside.
class SphereVolume extends EffectVolume {
  SphereVolume({
    required Vector3 center,
    required this.radius,
    required super.effect,
    required super.send,
  }) : assert(radius >= 0, 'radius cannot be negative'),
       center = center.clone();

  /// Centre of the sphere in scene space. Copied on construction, so the
  /// caller can't mutate it through the reference it passed in.
  final Vector3 center;

  /// Radius in scene units.
  final double radius;

  @override
  bool contains(Vector3 position) =>
      position.distanceToSquared(center) <= radius * radius;
}
