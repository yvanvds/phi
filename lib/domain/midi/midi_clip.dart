import 'midi_note.dart';

/// A named bag of [MidiNote]s with a meter.
///
/// Per Phi's vision (§3.7), clips are "interpreted, not played": the
/// `notes` list is the source material that a [MidiTransformChain] reads
/// and rewrites before anything reaches a voice.
///
/// The clip is **mutable** — the note-editing layer (issue #28) authors it
/// in place through a `ClipEditor` rather than rebuilding immutable copies.
/// The early-development immutability was an artifact; nothing depends on it.
/// Editing always goes through commands so the mutation stays undoable; the
/// raw [notes] list is exposed for transforms and painting to read.
class MidiClip {
  MidiClip({
    required this.name,
    required List<MidiNote> notes,
    required this.bars,
    this.beatsPerBar = 4,
  }) : notes = List<MidiNote>.of(notes);

  String name;

  /// Growable, mutable. Order is authoring order, not sorted by time — note
  /// identity inside an edit session is the list index, so callers must not
  /// reorder behind a [ClipEditor]'s back.
  final List<MidiNote> notes;

  int bars;
  int beatsPerBar;

  double get totalBeats => bars * beatsPerBar.toDouble();
}
