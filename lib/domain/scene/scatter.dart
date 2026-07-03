import 'dart:math';

import 'package:vector_math/vector_math_64.dart';

import 'scene_agent.dart';

/// A one-shot dispersal impulse over a set of [SceneAgent]s.
///
/// Vision §3.7: *"Once spawned, agents are subject to all the spatial
/// machinery — they can be grabbed, scattered, attracted..."* Scatter is the
/// stochastic one: it perturbs the live set by a bounded random kick, jolting
/// agents apart so a clustered spawn scatters into space.
///
/// Each agent's [SceneAgent.position] is nudged by a uniform per-axis amount
/// in `[-positionBound, +positionBound]`, and its [SceneAgent.velocity] by a
/// uniform per-axis amount in `[-velocityBound, +velocityBound]`. By default
/// scatter is a pure positional jolt ([velocityBound] `0`) — give it a
/// velocity bound as well to leave the agents drifting apart afterwards, so
/// the dispersal keeps playing out under [SceneField.step].
///
/// The impulse is **seedable and reproducible**, following the
/// [HumanizationTransform] idiom: [apply] builds a fresh `Random(seed)` each
/// call and walks the agents in order, drawing the position kick then the
/// velocity kick unconditionally and in a fixed order, so the same [seed] over
/// the same set always yields the same dispersal — a scatter is replayable.
/// Change the seed to audition a different throw.
///
/// Pure value type — [apply] returns fresh agents (via [SceneAgent.copyWith])
/// rather than mutating in place, so it never touches the source set.
class Scatter {
  const Scatter({
    this.positionBound = 1.0,
    this.velocityBound = 0.0,
    this.seed = 0,
  }) : assert(positionBound >= 0, 'positionBound cannot be negative'),
       assert(velocityBound >= 0, 'velocityBound cannot be negative');

  /// Maximum position kick per axis, applied symmetrically (±), in scene units.
  final double positionBound;

  /// Maximum velocity kick per axis, applied symmetrically (±), in scene units
  /// per second. Zero by default, so a bare scatter jolts positions only.
  final double velocityBound;

  /// Seed for the pseudo-random dispersal. Same seed + set ⇒ same throw.
  final int seed;

  /// Disperse [agents], returning a fresh list in the same order. Each agent's
  /// position and velocity are kicked by a bounded random impulse; everything
  /// else ([SceneAgent.voiceIndex], [SceneAgent.sends]) rides along untouched.
  ///
  /// The draw order is fixed — position kick (x, y, z) then velocity kick
  /// (x, y, z) per agent — so the RNG stream stays aligned across runs even
  /// when a bound is zero (the draws still happen, they just scale to nothing).
  List<SceneAgent> apply(Iterable<SceneAgent> agents) {
    final rng = Random(seed);
    return agents
        .map(
          (a) => a.copyWith(
            position: a.position + _impulse(rng, positionBound),
            velocity: a.velocity + _impulse(rng, velocityBound),
          ),
        )
        .toList(growable: false);
  }

  /// A per-axis uniform impulse bounded by [bound].
  Vector3 _impulse(Random rng, double bound) =>
      Vector3(_jitter(rng, bound), _jitter(rng, bound), _jitter(rng, bound));

  /// Uniform draw in `[-bound, +bound]`.
  double _jitter(Random rng, double bound) =>
      (rng.nextDouble() * 2 - 1) * bound;
}
