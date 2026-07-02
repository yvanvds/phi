import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/scale_tuning.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';

void main() {
  group('ScaleConformanceTransform (12-TET diatonic)', () {
    final cDorian = ScaleConformanceTransform.diatonic(
      scale: MusicScale.dorian,
      tonic: 60,
      label: 'c dorian',
    );

    double snap(num pitch) => cDorian
        .apply([
          MidiNote(pitch: pitch.toDouble(), start: 0, duration: 1, velocity: 1),
        ])
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

    test('snaps a fractional pitch to the nearest degree', () {
      // 61.4 sits nearer D (62) than C (60): snaps to D.
      expect(snap(61.4), 62);
      // 60.4 sits nearer C (60): snaps down to C.
      expect(snap(60.4), 60);
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

    test('copyWith flips active without losing tuning/tonic/label', () {
      final flipped = cDorian.copyWith(active: false);
      expect(flipped.tuning, same(cDorian.tuning));
      expect(flipped.tonic, 60);
      expect(flipped.label, 'c dorian');
      expect(flipped.active, isFalse);
    });
  });

  group('ScaleConformanceTransform (microtonal / non-12-TET)', () {
    double snapTo(ScaleTuning tuning, double tonic, double pitch) =>
        ScaleConformanceTransform(tuning: tuning, tonic: tonic, label: 't')
            .apply([MidiNote(pitch: pitch, start: 0, duration: 1, velocity: 1)])
            .single
            .pitch;

    test('snaps to a just-intonation major third (386.31 cents)', () {
      // C tonic at 60; the tempered E (64 = 400 cents) snaps to the JI major
      // third, 386.31 cents above C → 60 + 3.8631 semitones ≈ 63.863.
      final snapped = snapTo(ScaleTuning.justMajor, 60, 64);
      expect(snapped, closeTo(63.8631, 1e-3));
    });

    test('just-intonation tonic and octave stay exact', () {
      expect(snapTo(ScaleTuning.justMajor, 60, 60), closeTo(60, 1e-6));
      expect(snapTo(ScaleTuning.justMajor, 60, 72), closeTo(72, 1e-6));
    });

    test('an arbitrary cents table snaps to its nearest degree', () {
      // A quarter-tone scale: degrees every 50 cents within the octave.
      final quarterTone = ScaleTuning(
        degreesCents: [for (var c = 0.0; c < 1200; c += 50) c],
      );
      // 60.30 semitones = 30 cents above C → nearest degree is 50 cents
      // (60.5), since 30 is closer to 50 than to 0? No: 30 is closer to 0 (30)
      // than 50 (20)... 20 < 30, so it snaps up to 60.5.
      expect(snapTo(quarterTone, 60, 60.30), closeTo(60.5, 1e-6));
      // 60.10 (10 cents) is nearer 0 than 50 → snaps back to C.
      expect(snapTo(quarterTone, 60, 60.10), closeTo(60, 1e-6));
    });

    test('a non-octave period repeats the scale by that interval', () {
      // A toy 2-degree scale repeating every 600 cents (a tritone): degrees at
      // 0 and 300 cents. A note 700 cents above the tonic reduces to 100 cents
      // into the second period; nearest degree there is 0 (the period root at
      // 600) vs 300 — 100 is nearer 0, so it snaps to 600 cents = 66.
      const tritonePeriod = ScaleTuning(
        degreesCents: [0, 300],
        periodCents: 600,
      );
      expect(snapTo(tritonePeriod, 60, 67), closeTo(66, 1e-6));
    });
  });
}
