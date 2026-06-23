import '../midi_clip.dart';

/// One undoable edit to a [MidiClip]'s note list.
///
/// Commands are the only thing a [ClipEditor] pushes onto its undo/redo
/// stacks. [applyTo] performs the edit and records whatever state [revert]
/// needs to put the clip back exactly as it was. Because the editor replays
/// commands strictly LIFO, a command may capture absolute list indices at
/// [applyTo] time and trust them to still be valid when [revert] runs.
abstract class ClipEditCommand {
  /// Indices the selection should hold after this command is (re)applied —
  /// lets the editor keep "what you just touched" highlighted through
  /// redo, and after an undo the *inverse* command restores the prior set.
  Set<int> get affectedIndices;

  void applyTo(MidiClip clip);

  void revert(MidiClip clip);
}
