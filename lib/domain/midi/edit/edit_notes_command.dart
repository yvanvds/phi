import '../midi_note.dart';
import 'clip_edit_command.dart';

/// Replaces existing notes in place — the single command behind move, resize,
/// move-start and velocity edits. Each is just "these notes become those
/// notes" at unchanged indices, so the list length never changes and the
/// selection stays valid.
///
/// [before] and [after] are keyed by the same indices. [apply] writes `after`,
/// [revert] writes `before`.
class EditNotesCommand extends ClipEditCommand {
  EditNotesCommand(
    super.clip, {
    required Map<int, MidiNote> before,
    required Map<int, MidiNote> after,
    super.clipAddress,
  }) : assert(before.length == after.length),
       _before = Map<int, MidiNote>.of(before),
       _after = Map<int, MidiNote>.of(after);

  final Map<int, MidiNote> _before;
  final Map<int, MidiNote> _after;

  @override
  String get label =>
      _after.length == 1 ? 'edit note' : 'edit ${_after.length} notes';

  @override
  Set<int> get affectedIndices => _after.keys.toSet();

  @override
  void apply() {
    _after.forEach((i, note) => clip.notes[i] = note);
    clip.touch();
  }

  @override
  void revert() {
    _before.forEach((i, note) => clip.notes[i] = note);
    clip.touch();
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'edit_notes',
    'before': {
      for (final e in _before.entries) '${e.key}': noteToJson(e.value),
    },
    'after': {for (final e in _after.entries) '${e.key}': noteToJson(e.value)},
  };
}
