/// Facts about a MIDI pitch number that more than one surface draws from: the
/// 128-key range, which keys are black, and where a pitch sits on a staff
/// (issue #473).
///
/// Pure Dart. The keyboard (`.kslider`) and the staff (`.nslider`) both lay
/// out from here, so a key the keyboard paints black is the key the staff
/// spells with an accidental.
abstract final class MidiPitch {
  /// How many pitches MIDI has, 0–127.
  static const int count = 128;

  /// The highest pitch.
  static const int max = count - 1;

  /// The highest velocity a note-on carries (0 is a release).
  static const int maxVelocity = 127;

  /// Middle C.
  static const int middleC = 60;

  /// Pitch classes that are black keys: C♯ D♯ F♯ G♯ A♯.
  static const Set<int> _black = {1, 3, 6, 8, 10};

  /// [pitch] reduced to 0–11, C = 0, for negative pitches too.
  static int pitchClass(int pitch) => ((pitch % 12) + 12) % 12;

  /// Whether [pitch] is a black key.
  static bool isBlack(int pitch) => _black.contains(pitchClass(pitch));

  /// The letter index (C = 0 … B = 6) of each white pitch class.
  static const Map<int, int> _letterOfWhite = {
    0: 0,
    2: 1,
    4: 2,
    5: 3,
    7: 4,
    9: 5,
    11: 6,
  };

  /// [pitch]'s **diatonic step**: the staff position its note head takes, 7 per
  /// octave, counted from C of MIDI octave 0 (so middle C is step 35).
  ///
  /// A white key sits on its own letter. A black key sits on the letter below
  /// when spelled sharp ([accidental] above 0, or 0) and on the letter above
  /// when spelled flat ([accidental] below 0) — C♯ on C, D♭ on D.
  static int staffStep(int pitch, {int accidental = 0}) {
    final pc = pitchClass(pitch);
    final octave = (pitch - pc) ~/ 12;
    final letter =
        _letterOfWhite[pc] ??
        (accidental < 0 ? _letterOfWhite[pc + 1]! : _letterOfWhite[pc - 1]!);
    return octave * 7 + letter;
  }
}
