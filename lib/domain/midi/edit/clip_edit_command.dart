import '../../project/entity_address.dart';
import '../../project/project_command.dart';
import '../midi_clip.dart';
import '../midi_note.dart';

/// One undoable edit to a [MidiClip]'s note list — the MIDI surface's flavour
/// of [ProjectCommand] (issue #119 folds the clip-editor stack into the shared
/// command/undo-scope layer; design `docs/design/project-registry.md` §6).
///
/// A command binds its target [clip] at construction, so [apply]/[revert] take
/// no argument — the same self-contained shape every [ProjectCommand] uses.
/// Because a scope replays commands strictly LIFO, a command may capture
/// absolute list indices during [apply] and trust them at [revert].
///
/// [entitiesTouched] is empty until the clip becomes a registry entity (epic
/// issue 7); a [clipAddress] can be supplied ahead of that migration and, once
/// set, is what dirty-tracking (#121) and the journal (#122) will read.
abstract class ClipEditCommand implements ProjectCommand {
  ClipEditCommand(this.clip, {this.clipAddress});

  /// The clip this command edits.
  final MidiClip clip;

  /// The clip's registry address once it has one, else `null` (pre-migration).
  final EntityAddress? clipAddress;

  /// Indices the selection should hold after this command is (re)applied — lets
  /// the editor keep "what you just touched" highlighted through redo, and after
  /// an undo the *inverse* command restores the prior set. A MIDI-specific
  /// concern layered on top of [ProjectCommand].
  Set<int> get affectedIndices;

  @override
  Set<EntityAddress> get entitiesTouched =>
      clipAddress == null ? const {} : {clipAddress!};
}

/// Serialises a note to a JSON map for command journaling (§7). Shared by every
/// clip command so the encoding is defined once.
Map<String, Object?> noteToJson(MidiNote note) => {
  'pitch': note.pitch,
  'start': note.start,
  'duration': note.duration,
  'velocity': note.velocity,
  'channel': note.channel,
};
