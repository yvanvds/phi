import 'package:vector_math/vector_math_64.dart';

import 'effect_volume.dart';
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
/// This is the seam the rest of the spatial machinery hangs off. Effect
/// volumes (#80) live here as a set of [EffectVolume]s the field routes each
/// agent through every [step], surfacing the active sends on the agent;
/// scatter (#81) and grab (#82) will land as forces applied inside [step]
/// before integration, adjusting each agent's [SceneAgent.velocity].
class SceneField {
  final Map<int, SceneAgent> _agents = <int, SceneAgent>{};
  final List<EffectVolume> _volumes = <EffectVolume>[];

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

  /// Drop every agent. Leaves the effect volumes in place.
  void clear() => _agents.clear();

  /// A snapshot of the current effect volumes, in insertion order. Detached
  /// from internal state, so the caller can iterate without risk of mutation.
  List<EffectVolume> get volumes => _volumes.toList(growable: false);

  /// Add an effect volume. Agents inside it pick up its send on the next
  /// [step]. Volumes are placed programmatically for now.
  void addVolume(EffectVolume volume) => _volumes.add(volume);

  /// Remove [volume] by identity. Returns `true` if it was present.
  bool removeVolume(EffectVolume volume) => _volumes.remove(volume);

  /// Drop every effect volume. Agents keep whatever sends the last [step]
  /// assigned until the next step recomputes them against the empty set.
  void clearVolumes() => _volumes.clear();

  /// Advance every agent by [dt] seconds and route it through the effect
  /// volumes.
  ///
  /// Baseline integration is `position += velocity·dt`; each agent's active
  /// [SceneAgent.sends] are then recomputed from its *new* position, so an
  /// agent that drifts across a volume boundary this tick gains (or loses) the
  /// send the same step it crosses. Scatter and grab forces will hook in
  /// before integration in later issues. A non-positive [dt] is a no-op, so a
  /// paused or zero-length tick never nudges the field.
  void step(double dt) {
    if (dt <= 0 || _agents.isEmpty) return;
    for (final key in _agents.keys.toList(growable: false)) {
      final agent = _agents[key]!;
      final moved = agent.position + (agent.velocity * dt);
      _agents[key] = agent.copyWith(position: moved, sends: _sendsAt(moved));
    }
  }

  /// The effects sends active at [position]: every containing volume's effect
  /// tag mapped to its send amount. When two volumes carry the same effect the
  /// larger send wins, so an overlap never weakens the send. Empty when no
  /// volume contains the point.
  Map<String, double> _sendsAt(Vector3 position) {
    if (_volumes.isEmpty) return const <String, double>{};
    final sends = <String, double>{};
    for (final volume in _volumes) {
      if (!volume.contains(position)) continue;
      final existing = sends[volume.effect];
      if (existing == null || volume.send > existing) {
        sends[volume.effect] = volume.send;
      }
    }
    return sends;
  }
}
