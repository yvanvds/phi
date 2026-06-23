import '../midi_clip.dart';
import '../midi_note.dart';
import 'clip_edit_command.dart';

/// Removes a set of notes by index.
///
/// Records each removed `(index, note)` pair so [revert] can reinsert them at
/// their original positions. Removal runs high-index-first so earlier indices
/// stay valid mid-loop; reinsertion runs low-index-first so each note lands
/// back exactly where it came from.
class DeleteNotesCommand extends ClipEditCommand {
  DeleteNotesCommand(Iterable<int> indices)
    : _indices = (indices.toList()..sort());

  final List<int> _indices;
  final List<MidiNote> _removed = [];

  @override
  Set<int> get affectedIndices => const {};

  @override
  void applyTo(MidiClip clip) {
    _removed
      ..clear()
      ..addAll(_indices.map((i) => clip.notes[i]));
    for (final i in _indices.reversed) {
      clip.notes.removeAt(i);
    }
  }

  @override
  void revert(MidiClip clip) {
    for (var k = 0; k < _indices.length; k++) {
      clip.notes.insert(_indices[k], _removed[k]);
    }
  }
}
