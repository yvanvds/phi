import 'package:vector_math/vector_math_64.dart';

import '../agent_spawn.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import '../midi_transform_kind.dart';
import '../spawn_axis.dart';

/// Maps each note onto an [AgentSpawn] — a position in the 3D Scene, a voice
/// colour, and a lifetime — realising the vision's "each note-on spawns a
/// SceneAgent whose position derives from pitch/time/velocity/channel; the
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
/// the note's channel — the domain-side voice handle a [VoiceRoutingTransform]
/// earlier in the chain assigns — folded into the six-slot palette.
class AgentSpawnTransform extends MidiTransform {
  const AgentSpawnTransform({
    required this.x,
    required this.y,
    required this.z,
    required this.label,
    this.active = true,
  });

  /// Position axes. Each maps a chosen note scalar into a spatial coordinate.
  final SpawnAxis x;
  final SpawnAxis y;
  final SpawnAxis z;

  @override
  final String label;

  @override
  final bool active;

  @override
  MidiTransformKind get kind => MidiTransformKind.voice;

  @override
  List<MidiNote> apply(List<MidiNote> input) => input;

  @override
  AgentSpawnTransform copyWith({bool? active, String? label}) =>
      AgentSpawnTransform(
        x: x,
        y: y,
        z: z,
        label: label ?? this.label,
        active: active ?? this.active,
      );

  /// One [AgentSpawn] per note, in input order. The caller decides what
  /// "input" means — typically the note list at this transform's position in
  /// the chain.
  List<AgentSpawn> spawnsFor(List<MidiNote> input) =>
      input.map(spawnFor).toList(growable: false);

  /// The [AgentSpawn] a single [note] maps to.
  AgentSpawn spawnFor(MidiNote note) => AgentSpawn(
    position: Vector3(x.resolve(note), y.resolve(note), z.resolve(note)),
    voiceIndex: _voiceOf(note),
    startBeat: note.start,
    lifetimeBeats: note.duration,
  );

  /// Fold the note's channel into the six-slot voice palette (`0..5`).
  int _voiceOf(MidiNote note) => note.channel.clamp(0, 1 << 30) % 6;
}
