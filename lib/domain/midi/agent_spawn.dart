import 'package:vector_math/vector_math_64.dart';

/// A "spawn an agent at [position] for [lifetimeBeats]" instruction derived
/// from a note — the domain-side currency of the agent-spawn mapping, the
/// spatial sibling of [ParameterEvent].
///
/// [position] is in scene space. [voiceIndex] is `0..5`, the design-system
/// voice palette slot the renderer colours the agent with. [startBeat] is the
/// note's onset (same clock as `MidiNote.start`); [lifetimeBeats] is how long
/// the agent lives — the note's duration — after which it despawns (the
/// note-off).
///
/// Pure value type: the domain produces these, the engine bridge turns them
/// into live `SceneAgent`s. Kept independent of the scene domain so
/// `domain/midi` never depends on `domain/scene` — both merely share
/// `vector_math`.
class AgentSpawn {
  const AgentSpawn({
    required this.position,
    required this.voiceIndex,
    required this.startBeat,
    required this.lifetimeBeats,
  });

  final Vector3 position;
  final int voiceIndex;
  final double startBeat;
  final double lifetimeBeats;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentSpawn &&
          other.position == position &&
          other.voiceIndex == voiceIndex &&
          other.startBeat == startBeat &&
          other.lifetimeBeats == lifetimeBeats;

  @override
  int get hashCode =>
      Object.hash(position, voiceIndex, startBeat, lifetimeBeats);

  @override
  String toString() =>
      'AgentSpawn(pos:$position voice:$voiceIndex '
      'start:$startBeat life:$lifetimeBeats)';
}
