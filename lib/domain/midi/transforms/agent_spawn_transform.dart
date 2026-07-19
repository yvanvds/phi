import 'package:vector_math/vector_math_64.dart';

import '../agent_spawn.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../spawn_axis.dart';
import '../voice_hash.dart';

/// Maps each note onto an [AgentSpawn] — a position in the 3D Scene, a voice
/// colour, and a lifetime — realising the vision's "each note-on spawns a
/// SceneAgent whose position derives from pitch/time/velocity/voice; the
/// agent lives for the note's duration" (§3.7, issue #37).
///
/// Notes themselves pass through [apply] untouched: like
/// [VelocityToParameterTransform] this stage routes *spatial* data, not note
/// data, so toggling it never changes the piano roll. Consumers pull the
/// spawn stream with [spawnsFor] (or [spawnFor] for a single note), feeding it
/// the note list the chain handed to this stage.
///
/// Each of [x], [y], [z] is an independent [SpawnAxis], so position can bind
/// any axis to any note dimension. The agent's voice colour is derived from
/// the note's routed voice — the `voice.` address a [VoiceRoutingTransform]
/// earlier in the chain assigns — folded into the six-slot palette.
///
/// [velocity] stamps every spawn with an initial motion (scene units per
/// second) the scene's `SceneField` integrates each tick — zero by default, so
/// nothing drifts unless asked. A constant drift is the foundation baseline
/// (issue #79); per-note velocity mapping is a natural later extension.
class AgentSpawnTransform extends MidiTransform {
  AgentSpawnTransform({
    required this.x,
    required this.y,
    required this.z,
    required this.label,
    this.active = true,
    Vector3? velocity,
  }) : velocity = velocity ?? Vector3.zero();

  /// Position axes. Each maps a chosen note scalar into a spatial coordinate.
  final SpawnAxis x;
  final SpawnAxis y;
  final SpawnAxis z;

  /// Constant initial velocity stamped on every spawn (scene units / second).
  final Vector3 velocity;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.voice;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input;

  /// Carries the [x]/[y]/[z] axes and [velocity] drift alongside the base
  /// [active]/[label] so the typed spawn editor (issue #95) can rebind any
  /// axis or the drift in place without losing the chip's toggle or name.
  @override
  AgentSpawnTransform copyWith({
    bool? active,
    String? label,
    SpawnAxis? x,
    SpawnAxis? y,
    SpawnAxis? z,
    Vector3? velocity,
  }) => AgentSpawnTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    label: label ?? this.label,
    active: active ?? this.active,
    velocity: velocity ?? this.velocity,
  );

  /// One [AgentSpawn] per note, in input order. The caller decides what
  /// "input" means — typically the note list at this transform's position in
  /// the chain.
  List<AgentSpawn> spawnsFor(List<MidiNote> input) =>
      input.map(spawnFor).toList(growable: false);

  /// The [AgentSpawn] a single [note] maps to.
  AgentSpawn spawnFor(MidiNote note) => AgentSpawn(
    position: Vector3(x.resolve(note), y.resolve(note), z.resolve(note)),
    velocity: velocity.clone(),
    voiceIndex: _voiceOf(note),
    startBeat: note.start,
    lifetimeBeats: note.duration,
  );

  /// Fold the note's routed voice into the six-slot voice palette (`0..5`) via
  /// its stable [voiceHash] — an unrouted note (`voice == null`) folds to `0`.
  int _voiceOf(MidiNote note) => voiceHash(note.voice) % 6;
}
