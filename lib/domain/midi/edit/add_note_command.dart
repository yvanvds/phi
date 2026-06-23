import '../midi_clip.dart';
import '../midi_note.dart';
import 'clip_edit_command.dart';

/// Appends a single [MidiNote] to the clip.
///
/// The note is appended (never inserted mid-list) so existing indices — and
/// therefore any live selection — stay valid. [revert] removes the note at
/// the index it landed on.
class AddNoteCommand extends ClipEditCommand {
  AddNoteCommand(this.note);

  final MidiNote note;
  int? _index;

  @override
  Set<int> get affectedIndices => _index == null ? const {} : {_index!};

  @override
  void applyTo(MidiClip clip) {
    _index = clip.notes.length;
    clip.notes.add(note);
  }

  @override
  void revert(MidiClip clip) {
    clip.notes.removeAt(_index!);
  }
}
