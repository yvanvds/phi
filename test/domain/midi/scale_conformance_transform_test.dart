import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';

void main() {
  group('ScaleConformanceTransform', () {
    const cDorian = ScaleConformanceTransform(
      scale: MusicScale.dorian,
      tonic: 60,
      label: 'c dorian',
    );

    int snap(int pitch) => cDorian
        .apply([MidiNote(pitch: pitch, start: 0, duration: 1, velocity: 1)])
        .single
        .pitch;

    test('in-scale pitches pass through unchanged', () {
      // C-dorian: C D Eb F G A Bb
      expect(snap(60), 60); // C
      expect(snap(62), 62); // D
      expect(snap(63), 63); // Eb
      expect(snap(65), 65); // F
      expect(snap(67), 67); // G
      expect(snap(69), 69); // A
      expect(snap(70), 70); // Bb
    });

    test('off-scale pitches resolve ties upward (the default tie-break)', () {
      // Every chromatic pitch in a diatonic scale sits equidistant between
      // two scale degrees; Phi prefers the brighter (upward) neighbour.
      expect(snap(61), 62); // C# → D
      expect(snap(64), 65); // E  → F
      expect(snap(66), 67); // F# → G
      expect(snap(68), 69); // G# → A
    });

    test(
      'crosses the octave boundary when the up-neighbour is the next root',
      () {
        // B is equidistant from Bb (in C-dorian) and the next octave's C;
        // tie-break upward picks C7.
        expect(snap(71), 72);
        expect(snap(95), 96); // B6 → C7
      },
    );

    test('clamps the result to the 7-bit MIDI range', () {
      // pitch=0 has pc=0 (C) — already in scale.
      expect(snap(0), 0);
      // pitch=127 has pc=7 (G) — already in scale.
      expect(snap(127), 127);
    });

    test('preserves start, duration, velocity, and channel', () {
      final out = cDorian.apply(const [
        MidiNote(
          pitch: 61,
          start: 0.5,
          duration: 0.25,
          velocity: 0.42,
          channel: 5,
        ),
      ]);
      expect(
        out.single,
        const MidiNote(
          pitch: 62,
          start: 0.5,
          duration: 0.25,
          velocity: 0.42,
          channel: 5,
        ),
      );
    });

    test('copyWith flips active without losing scale/tonic/label', () {
      final flipped = cDorian.copyWith(active: false);
      expect(flipped.scale, MusicScale.dorian);
      expect(flipped.tonic, 60);
      expect(flipped.label, 'c dorian');
      expect(flipped.active, isFalse);
    });
  });
}
