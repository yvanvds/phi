import 'package:vector_math/vector_math_64.dart';

import 'effect_volume.dart';
import 'pick_ray.dart';
import 'scatter.dart';
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
/// [scatter] (#81) is a one-shot [Scatter] impulse that disperses the set;
/// grab (#82) is a held target the field pulls an agent toward inside [step],
/// before integration — see [grab] / [moveGrabTo] / [release]. Code can pick
/// ([pick]) and grab an agent exactly as the Scene surface's pointer will.
class SceneField {
  /// Builds a field. [grabStrength] is the fraction of the remaining distance
  /// a grabbed agent is pulled toward its target each [step] — `1` snaps it
  /// rigidly, smaller values lag behind for a springier feel. Must be in
  /// `(0, 1]`.
  SceneField({this.grabStrength = _defaultGrabStrength})
    : assert(
        grabStrength > 0 && grabStrength <= 1,
        'grabStrength must be in (0, 1]',
      );

  static const double _defaultGrabStrength = 0.5;

  /// A comfortable pick radius, in scene units — mirrors the renderer's halo
  /// so the clickable target matches the glowing dot the performer sees.
  static const double defaultPickRadius = 0.55;

  final Map<int, SceneAgent> _agents = <int, SceneAgent>{};
  final List<EffectVolume> _volumes = <EffectVolume>[];

  /// How hard a held agent is pulled toward its grab target each [step].
  final double grabStrength;

  /// The key of the agent currently held by a grab, or `null` when nothing is
  /// grabbed.
  int? _grabbedKey;

  /// Where the held agent is being pulled toward. Non-null exactly while
  /// [isGrabbing]. Stored cloned so a caller can't mutate it behind our back.
  Vector3? _grabTarget;

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

  /// Remove the agent under [key]. Returns `true` if one was present. If the
  /// removed agent was the one being grabbed, the grab is released too — a
  /// held agent that despawns can't keep being pulled.
  bool despawn(int key) {
    final removed = _agents.remove(key) != null;
    if (removed && key == _grabbedKey) release();
    return removed;
  }

  /// Drop every agent, releasing any active grab. Leaves the effect volumes in
  /// place.
  void clear() {
    _agents.clear();
    release();
  }

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

  /// Whether an agent is currently held by a grab.
  bool get isGrabbing => _grabbedKey != null;

  /// The key of the agent currently grabbed, or `null` when nothing is held.
  int? get grabbedKey => _grabbedKey;

  /// Begin grabbing the agent under [key] — the start of a direct-manipulation
  /// pull. The target seeds to the agent's current position, so the agent
  /// doesn't jump until [moveGrabTo] drags the target elsewhere. Grabbing a new
  /// key replaces any previous grab. Returns `true` if an agent was present;
  /// `false` (and no grab) when [key] holds nothing.
  bool grab(int key) {
    final agent = _agents[key];
    if (agent == null) return false;
    _grabbedKey = key;
    _grabTarget = agent.position.clone();
    return true;
  }

  /// Move the held target the grabbed agent is pulled toward. A no-op when
  /// nothing is grabbed, so a stray drag without a grab never perturbs the
  /// field.
  void moveGrabTo(Vector3 target) {
    if (_grabbedKey == null) return;
    _grabTarget = target.clone();
  }

  /// Release the grab, handing motion back to the field. The agent keeps
  /// whatever velocity the pull built up on the last [step], so a grab that
  /// was still moving throws the agent and one held steady lets it settle. A
  /// no-op when nothing is grabbed.
  void release() {
    _grabbedKey = null;
    _grabTarget = null;
  }

  /// The key of the agent under [ray] — the nearest one whose sphere (of
  /// [radius], defaulting to [defaultPickRadius]) the ray strikes — or `null`
  /// when the ray hits none. Ties on distance keep the earlier-spawned agent.
  ///
  /// This is the pick half of direct manipulation: the Scene surface turns a
  /// pointer into a [PickRay] and hands the resulting key to [grab]; code can
  /// build a ray and pick without any viewport at all.
  int? pick(PickRay ray, {double radius = defaultPickRadius}) {
    int? nearestKey;
    var nearestDistance = double.infinity;
    for (final entry in _agents.entries) {
      final distance = ray.hitSphere(entry.value.position, radius);
      if (distance != null && distance < nearestDistance) {
        nearestDistance = distance;
        nearestKey = entry.key;
      }
    }
    return nearestKey;
  }

  /// Advance every agent by [dt] seconds and route it through the effect
  /// volumes.
  ///
  /// A grabbed agent is pulled toward its held target first: it moves
  /// [grabStrength] of the remaining distance this step, and that displacement
  /// becomes its velocity (over [dt]) so a [release] mid-motion throws it while
  /// a settled grab throws nothing. Every other agent integrates by the
  /// baseline `position += velocity·dt`. Each agent's active [SceneAgent.sends]
  /// are then recomputed from its *new* position, so an agent that drifts (or
  /// is dragged) across a volume boundary this tick gains or loses the send the
  /// same step it crosses. A non-positive [dt] is a no-op, so a paused or
  /// zero-length tick never nudges the field.
  void step(double dt) {
    if (dt <= 0 || _agents.isEmpty) return;
    final grabbedKey = _grabbedKey;
    final grabTarget = _grabTarget;
    for (final key in _agents.keys.toList(growable: false)) {
      final agent = _agents[key]!;
      final Vector3 moved;
      final Vector3 velocity;
      if (key == grabbedKey && grabTarget != null) {
        moved = agent.position + (grabTarget - agent.position) * grabStrength;
        velocity = (moved - agent.position) / dt;
      } else {
        moved = agent.position + (agent.velocity * dt);
        velocity = agent.velocity;
      }
      _agents[key] = agent.copyWith(
        position: moved,
        velocity: velocity,
        sends: _sendsAt(moved),
      );
    }
  }

  /// Disperse the live agents with a one-shot [scatter] impulse — a seeded,
  /// bounded random kick to every agent's position (and velocity). Keys are
  /// preserved, so a later despawn still removes exactly the agent its spawn
  /// added; only the motion state is perturbed.
  ///
  /// Deterministic and replayable: the same [Scatter] over the same field
  /// state always produces the same throw. Sends are left as the last [step]
  /// assigned — the next [step] recomputes them from each agent's kicked
  /// position. A no-op when no agents are alive.
  void scatter(Scatter scatter) {
    if (_agents.isEmpty) return;
    final keys = _agents.keys.toList(growable: false);
    final dispersed = scatter.apply(keys.map((key) => _agents[key]!));
    for (var i = 0; i < keys.length; i++) {
      _agents[keys[i]] = dispersed[i];
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
