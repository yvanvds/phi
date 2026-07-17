import '../midi_note.dart';
import 'clip_edit_command.dart';

/// Appends a single [MidiNote] to the clip.
///
/// The note is appended (never inserted mid-list) so existing indices — and
/// therefore any live selection — stay valid. [revert] removes the note at
/// the index it landed on.
class AddNoteCommand extends ClipEditCommand {
  AddNoteCommand(super.clip, this.note, {super.clipAddress});

  final MidiNote note;
  int? _index;

  @override
  String get label => 'add note';

  @override
  Set<int> get affectedIndices => _index == null ? const {} : {_index!};

  @override
  void apply() {
    _index = clip.notes.length;
    clip.notes.add(note);
    clip.touch();
  }

  @override
  void revert() {
    clip.notes.removeAt(_index!);
    clip.touch();
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'add_note',
    'note': noteToJson(note),
  };
}
