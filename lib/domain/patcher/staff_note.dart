import '../midi/midi_pitch.dart';

/// Where an `.nslider` draws its note on the grand staff (issue #473): the
/// diatonic [step] of the head, its [accidental], the [ledgers] it needs, and
/// an [ottava] when the pitch lies past the window the staff shows.
///
/// Steps are [MidiPitch.staffStep]'s, 7 to an octave with middle C at 35. The
/// staff shows [lowStep]–[highStep] — two ledger lines past either staff. A
/// note beyond is drawn whole octaves nearer and marked: [ottava] 1 is *8va*
/// (sounds an octave above where it is drawn), -1 *8vb*, 2 *15ma*, and so on.
class StaffNote {
  const StaffNote({
    required this.step,
    required this.accidental,
    required this.ottava,
  });

  /// [pitch] spelled with [accidental] (1 sharp, -1 flat, 0 natural), as the
  /// object reports its two cells.
  factory StaffNote.of(int pitch, int accidental) {
    final sign = MidiPitch.isBlack(pitch) ? accidental.sign : 0;
    var step = MidiPitch.staffStep(pitch, accidental: sign);
    var ottava = 0;
    while (step > highStep) {
      step -= 7;
      ottava++;
    }
    while (step < lowStep) {
      step += 7;
      ottava--;
    }
    return StaffNote(step: step, accidental: sign, ottava: ottava);
  }

  /// The lowest step drawn: C2, two ledger lines under the bass staff.
  static const int lowStep = 21;

  /// The highest step drawn: C6, two ledger lines over the treble staff.
  static const int highStep = 49;

  /// Middle C, on its own ledger line between the staves.
  static const int middleC = 35;

  /// The bass staff's five lines, G2 to A3.
  static const List<int> bassLines = [25, 27, 29, 31, 33];

  /// The treble staff's five lines, E4 to F5.
  static const List<int> trebleLines = [37, 39, 41, 43, 45];

  /// The diatonic step the head sits on, inside [lowStep]–[highStep].
  final int step;

  /// 1 sharp, -1 flat, 0 natural (always 0 on a white key).
  final int accidental;

  /// Octaves the note is drawn nearer the staves than it sounds.
  final int ottava;

  /// The ledger lines the head needs, as steps.
  List<int> get ledgers => [
    if (step == middleC) middleC,
    for (var s = bassLines.first - 2; s >= step; s -= 2) s,
    for (var s = trebleLines.last + 2; s <= step; s += 2) s,
  ];

  @override
  bool operator ==(Object other) =>
      other is StaffNote &&
      other.step == step &&
      other.accidental == accidental &&
      other.ottava == ottava;

  @override
  int get hashCode => Object.hash(step, accidental, ottava);

  @override
  String toString() =>
      'StaffNote(step: $step, accidental: $accidental, ottava: $ottava)';
}
