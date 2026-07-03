import 'package:vector_math/vector_math_64.dart';

/// A single agent in the 3D scene.
///
/// Carries the minimal per-agent motion state a [SceneField] needs to advance
/// it: a [position] and a [velocity]. Baseline motion is `position +=
/// velocity·dt` (see [SceneField.step]); attraction, effect volumes, scatter,
/// and grab arrive in later issues (#80–#82) as forces that modify [velocity].
///
/// Pure value type — immutable, so stepping produces a fresh agent via
/// [copyWith] rather than mutating in place. The [voiceIndex] the renderer
/// maps to a design-system colour rides along untouched.
class SceneAgent {
  SceneAgent({required this.position, Vector3? velocity, this.voiceIndex = 0})
    : velocity = velocity ?? Vector3.zero();

  /// Position in scene space.
  final Vector3 position;

  /// Velocity in scene units per second. Zero by default — a spawned agent
  /// sits still until something (a spawn drift, a force) gives it motion.
  final Vector3 velocity;

  /// 0..5 — index into the voice palette (voice1..voice6).
  final int voiceIndex;

  /// A copy with selected fields replaced. Vectors are copied, not shared, so
  /// the source agent's [position] / [velocity] can't be mutated through the
  /// clone (`vector_math`'s Vector3 is mutable).
  SceneAgent copyWith({
    Vector3? position,
    Vector3? velocity,
    int? voiceIndex,
  }) => SceneAgent(
    position: position != null ? position.clone() : this.position.clone(),
    velocity: velocity != null ? velocity.clone() : this.velocity.clone(),
    voiceIndex: voiceIndex ?? this.voiceIndex,
  );
}
