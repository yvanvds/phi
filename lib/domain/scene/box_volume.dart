import 'package:vector_math/vector_math_64.dart';

import 'effect_volume.dart';

/// An axis-aligned box [EffectVolume] — the AABB between [min] and [max].
///
/// Each corner is copied on construction and normalised so [min] holds the
/// component-wise smaller values and [max] the larger, letting the caller pass
/// the two corners in any order. Membership is inclusive on every face.
class BoxVolume extends EffectVolume {
  BoxVolume({
    required Vector3 corner,
    required Vector3 opposite,
    required super.effect,
    required super.send,
  }) : min = Vector3(
         corner.x < opposite.x ? corner.x : opposite.x,
         corner.y < opposite.y ? corner.y : opposite.y,
         corner.z < opposite.z ? corner.z : opposite.z,
       ),
       max = Vector3(
         corner.x > opposite.x ? corner.x : opposite.x,
         corner.y > opposite.y ? corner.y : opposite.y,
         corner.z > opposite.z ? corner.z : opposite.z,
       );

  /// The corner with the component-wise smaller coordinates.
  final Vector3 min;

  /// The corner with the component-wise larger coordinates.
  final Vector3 max;

  @override
  bool contains(Vector3 position) =>
      position.x >= min.x &&
      position.x <= max.x &&
      position.y >= min.y &&
      position.y <= max.y &&
      position.z >= min.z &&
      position.z <= max.z;
}
