import 'package:vector_math/vector_math_64.dart';

/// A single agent in the 3D scene.
///
/// Phase 1 model — position plus a voice index that the renderer maps to a
/// design-system colour. Swarms, velocity, attraction, and sonic identity
/// arrive in later issues.
class SceneAgent {
  SceneAgent({required this.position, this.voiceIndex = 0});

  /// Position in scene space.
  final Vector3 position;

  /// 0..5 — index into the voice palette (voice1..voice6).
  final int voiceIndex;
}
