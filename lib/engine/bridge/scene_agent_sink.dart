import '../../domain/scene/scene_agent.dart';

/// The narrow slice of the Scene the MIDI player writes live agents to.
///
/// `EngineMidiController` spawns and despawns agents as a clip plays, but it
/// has no business touching camera, lifecycle, or the render widget — so it
/// depends on this one-method port rather than the whole [SceneRenderer].
/// [SceneRenderer] implements it, so the production renderer (and the test
/// `FakeSceneRenderer`) satisfies it directly; nothing extra to wire.
abstract interface class SceneAgentSink {
  /// Replace the current agent set. Reflected on the next frame.
  void setAgents(List<SceneAgent> agents);
}
