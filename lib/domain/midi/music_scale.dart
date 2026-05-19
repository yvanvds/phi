/// Diatonic modes Phi knows how to snap MIDI pitches to.
///
/// [intervals] are semitone offsets from the scale's tonic. The list is
/// always sorted ascending and starts at 0; the next octave begins at 12.
enum MusicScale {
  ionian('ionian', [0, 2, 4, 5, 7, 9, 11]),
  dorian('dorian', [0, 2, 3, 5, 7, 9, 10]),
  phrygian('phrygian', [0, 1, 3, 5, 7, 8, 10]),
  lydian('lydian', [0, 2, 4, 6, 7, 9, 11]),
  mixolydian('mixolydian', [0, 2, 4, 5, 7, 9, 10]),
  aeolian('aeolian', [0, 2, 3, 5, 7, 8, 10]),
  locrian('locrian', [0, 1, 3, 5, 6, 8, 10]);

  const MusicScale(this.label, this.intervals);

  final String label;
  final List<int> intervals;
}
