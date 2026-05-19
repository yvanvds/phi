import 'midi_note.dart';

/// A named bag of [MidiNote]s with a meter.
///
/// Per Phi's vision (§3.7), clips are "interpreted, not played": the
/// `notes` list is the source material that a [MidiTransformChain] reads
/// and rewrites before anything reaches a voice.
class MidiClip {
  const MidiClip({
    required this.name,
    required this.notes,
    required this.bars,
    this.beatsPerBar = 4,
  });

  final String name;
  final List<MidiNote> notes;
  final int bars;
  final int beatsPerBar;

  double get totalBeats => bars * beatsPerBar.toDouble();
}
