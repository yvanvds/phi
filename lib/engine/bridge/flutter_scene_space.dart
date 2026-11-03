import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:vector_math/vector_math_64.dart';

import '../../domain/scene/pick_ray.dart';
import 'camera.dart';
import 'scene_unproject.dart';

/// The mapping between Phi's scene space and `flutter_scene`'s world.
///
/// Phi's scene is right-handed with +Z up (`SceneField`, the spawn axes, the
/// orbit camera). `flutter_scene` is left-handed with +Y up. Swapping the Y and
/// Z axes turns one into the other — a swap of two axes flips handedness — so a
/// Phi point `(x, y, z)` sits at `(x, z, y)` in the engine and the picture is
/// not mirrored. Everything that crosses the renderer boundary goes through
/// here, and [viewProjection] folds the swap into the camera matrix so the pure
/// [SceneUnproject] math returns rays straight in Phi space.
class FlutterSceneSpace {
  const FlutterSceneSpace._();

  /// A Phi scene-space point in the engine's world.
  static vm32.Vector3 toEngine(Vector3 v) => vm32.Vector3(v.x, v.z, v.y);

  /// An engine world point in Phi's scene space.
  static Vector3 fromEngine(vm32.Vector3 v) => Vector3(v.x, v.z, v.y);

  /// The engine camera for a Phi [camera] — same eye, target and vertical
  /// field of view, with the engine's +Y (Phi's +Z) up.
  static fs.PerspectiveCamera engineCamera(Camera camera) =>
      fs.PerspectiveCamera(
        position: toEngine(camera.position),
        target: toEngine(camera.target),
        up: vm32.Vector3(0, 1, 0),
        fovRadiansY: camera.fovYRadians,
      );

  /// The combined projection × view matrix the engine draws [camera] with in a
  /// [viewport] (logical pixels), taking *Phi* scene-space points to clip
  /// space. The engine's clip depth runs 0..1 rather than -1..1; the pick ray
  /// does not care, it only needs two points along the pixel's line of sight.
  static Matrix4 viewProjection(Camera camera, Size viewport) {
    final engine = engineCamera(camera).getViewTransform(viewport);
    return Matrix4.fromList(engine.storage.toList())..multiply(_phiToEngine);
  }

  /// The Phi scene-space [PickRay] through the pointer at [position] (logical
  /// pixels, origin top-left) in a [viewport] seen through [camera].
  static PickRay rayThrough(Camera camera, Offset position, Size viewport) =>
      SceneUnproject.rayThrough(
        viewProjection: viewProjection(camera, viewport),
        width: viewport.width,
        height: viewport.height,
        x: position.dx,
        y: position.dy,
      );

  /// Where the Phi scene-space [point] lands in a [viewport] seen through
  /// [camera], in logical pixels (origin top-left), or `null` when it sits
  /// behind the camera.
  static Offset? project(Camera camera, Vector3 point, Size viewport) {
    final clip = viewProjection(
      camera,
      viewport,
    ).transform(Vector4(point.x, point.y, point.z, 1));
    if (clip.w <= 0) return null;
    return Offset(
      (clip.x / clip.w + 1) / 2 * viewport.width,
      (1 - clip.y / clip.w) / 2 * viewport.height,
    );
  }

  /// The Y↔Z swap, as a matrix acting on Phi points.
  static final Matrix4 _phiToEngine = Matrix4.columns(
    Vector4(1, 0, 0, 0),
    Vector4(0, 0, 1, 0),
    Vector4(0, 1, 0, 0),
    Vector4(0, 0, 0, 1),
  );
}
