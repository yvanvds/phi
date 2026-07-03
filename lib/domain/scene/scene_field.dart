import 'scene_agent.dart';

/// The live agent set of the 3D Scene, and the clock that advances it.
///
/// Pure-Dart, headless, and deterministic: it owns a keyed collection of
/// [SceneAgent]s and a [step] that integrates their motion by an explicit
/// `dt` (seconds). No wall clock — the caller (the engine's MIDI player)
/// passes the tick delta — so a run replays identically given the same spawns
/// and deltas.
///
/// Agents are keyed by an opaque `int` the caller owns (the player uses its
/// per-voice note key), so a despawn removes exactly the agent its spawn
/// added, independent of iteration order.
///
/// This is the seam the rest of the spatial machinery (effect volumes #80,
/// scatter #81, grab #82) hangs off: those land as forces applied inside
/// [step] before integration, adjusting each agent's [SceneAgent.velocity].
/// For this foundation slice the only motion is the constant-velocity
/// baseline.
class SceneField {
  final Map<int, SceneAgent> _agents = <int, SceneAgent>{};

  /// Whether no agents are currently alive.
  bool get isEmpty => _agents.isEmpty;

  /// How many agents are currently alive.
  int get length => _agents.length;

  /// A snapshot of the current agents, in insertion order. Fixed-length and
  /// detached from internal state, so the caller can hand it straight to the
  /// renderer without risk of later mutation.
  List<SceneAgent> get agents => _agents.values.toList(growable: false);

  /// Add (or replace) the agent under [key]. Replacing lets a re-triggered
  /// voice key overwrite a stale agent rather than leaking it.
  void spawn(int key, SceneAgent agent) => _agents[key] = agent;

  /// Remove the agent under [key]. Returns `true` if one was present.
  bool despawn(int key) => _agents.remove(key) != null;

  /// Drop every agent.
  void clear() => _agents.clear();

  /// Advance every agent by [dt] seconds.
  ///
  /// Baseline integration is `position += velocity·dt`. Forces (attraction,
  /// effect volumes, scatter) will hook in here before this line in later
  /// issues, mutating each agent's velocity first. A non-positive [dt] is a
  /// no-op, so a paused or zero-length tick never nudges the field.
  void step(double dt) {
    if (dt <= 0 || _agents.isEmpty) return;
    for (final key in _agents.keys.toList(growable: false)) {
      final agent = _agents[key]!;
      _agents[key] = agent.copyWith(
        position: agent.position + (agent.velocity * dt),
      );
    }
  }
}
