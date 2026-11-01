import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_pitch.dart';

void main() {
  test('black keys are the five accidentals of each octave', () {
    final black = [
      for (var p = 60; p < 72; p++)
        if (MidiPitch.isBlack(p)) p,
    ];
    expect(black, [61, 63, 66, 68, 70]);
    expect(MidiPitch.isBlack(-11), isTrue, reason: 'pitch class 1');
  });

  test('a white key sits on its own letter, middle C at step 35', () {
    expect(MidiPitch.staffStep(60), 35);
    expect(MidiPitch.staffStep(62), 36);
    expect(MidiPitch.staffStep(71), 41);
    expect(MidiPitch.staffStep(72), 42);
    expect(MidiPitch.staffStep(0), 0);
  });

  test('a black key sits on the letter below as a sharp, above as a flat', () {
    expect(MidiPitch.staffStep(61, accidental: 1), 35, reason: 'C sharp');
    expect(MidiPitch.staffStep(61, accidental: -1), 36, reason: 'D flat');
    expect(MidiPitch.staffStep(70), 40, reason: 'A sharp by default');
    expect(MidiPitch.staffStep(70, accidental: -1), 41, reason: 'B flat');
  });
}
