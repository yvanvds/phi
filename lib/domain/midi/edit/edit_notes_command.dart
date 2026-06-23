import '../midi_clip.dart';
import '../midi_note.dart';
import 'clip_edit_command.dart';

/// Replaces existing notes in place — the single command behind move, resize,
/// move-start and velocity edits. Each is just "these notes become those
/// notes" at unchanged indices, so the list length never changes and the
/// selection stays valid.
///
/// [before] and [after] are keyed by the same indices. [applyTo] writes
/// `after`, [revert] writes `before`.
class EditNotesCommand extends ClipEditCommand {
  EditNotesCommand({
    required Map<int, MidiNote> before,
    required Map<int, MidiNote> after,
  }) : assert(before.length == after.length),
       _before = Map<int, MidiNote>.of(before),
       _after = Map<int, MidiNote>.of(after);

  final Map<int, MidiNote> _before;
  final Map<int, MidiNote> _after;

  @override
  Set<int> get affectedIndices => _after.keys.toSet();

  @override
  void applyTo(MidiClip clip) {
    _after.forEach((i, note) => clip.notes[i] = note);
  }

  @override
  void revert(MidiClip clip) {
    _before.forEach((i, note) => clip.notes[i] = note);
  }
}
