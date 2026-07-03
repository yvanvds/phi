import 'package:vector_math/vector_math_64.dart';

import 'scene_agent.dart';

/// A small, hand-tuned set of agents for exercising the Scene surface's
/// pick / select / grab by hand (issue #90).
///
/// The playback demo spawns agents that are short-lived (its notes are a
/// fraction of a beat, so an agent despawns before it can be clicked) and
/// clustered (its spawn axes map several close-together notes into a tight
/// region), which makes the pointer path awkward to test manually. This preset
/// sidesteps both: a handful of **long-lived** (they never despawn on their
/// own) and **well-separated** (each pair sits several scene units apart, far
/// beyond the pick radius) agents, each on a distinct voice colour so they're
/// easy to tell apart.
///
/// Positions are laid out around the origin so the default orbit camera
/// (looking at the origin, +Z up) frames them all. Velocity is zero — the
/// agents sit still until the performer grabs one — so picking is a stationary
/// target rather than a moving one.
List<SceneAgent> pickDemoAgents() => <SceneAgent>[
  SceneAgent(position: Vector3(-3, 0, 0), voiceIndex: 0),
  SceneAgent(position: Vector3(3, 0, 0), voiceIndex: 1),
  SceneAgent(position: Vector3(0, -3, 1.5), voiceIndex: 2),
  SceneAgent(position: Vector3(0, 3, -1.5), voiceIndex: 3),
  SceneAgent(position: Vector3(0, 0, 3), voiceIndex: 4),
];
