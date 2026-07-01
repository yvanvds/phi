import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/inversion_transform.dart';

void main() {
  group('InversionTransform', () {
    test('mirrors pitches around an integer axis', () {
      const t = InversionTransform(axis: 60, label: 'around C4');
      final out = t.apply(const [
        MidiNote(pitch: 64, start: 0, duration: 1, velocity: 1), // +4
        MidiNote(pitch: 55, start: 1, duration: 1, velocity: 1), // -5
      ]);
      // 2*60-64 = 56, 2*60-55 = 65.
      expect(out.map((n) => n.pitch), [56, 65]);
    });

    test('leaves a note sitting on an integer axis unmoved', () {
      const t = InversionTransform(axis: 60, label: 'around C4');
      expect(
        t
            .apply(const [
              MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        60,
      );
    });

    test('a half-integer axis has no fixed point on played notes', () {
      // Mirror between C4 (60) and D4 (62): axis 61 keeps E-neighbours
      // symmetric; here use 60.5 to swap 60↔61.
      const t = InversionTransform(axis: 60.5, label: 'between C4/C#4');
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        MidiNote(pitch: 61, start: 1, duration: 1, velocity: 1),
      ]);
      expect(out.map((n) => n.pitch), [61, 60]);
    });

    test('rounds a fractional reflection to the nearest semitone', () {
      // axis 60.25 → 2*60.25 - 64 = 56.5 → rounds to 57 (round-half-up).
      const t = InversionTransform(axis: 60.25, label: 'quarter axis');
      expect(
        t
            .apply(const [
              MidiNote(pitch: 64, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        57,
      );
    });

    test('clamps reflected pitches to the 7-bit MIDI range', () {
      const low = InversionTransform(axis: 10, label: 'low axis');
      // 2*10 - 100 = -80 → clamps to 0.
      expect(
        low
            .apply(const [
              MidiNote(pitch: 100, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        0,
      );
      const high = InversionTransform(axis: 120, label: 'high axis');
      // 2*120 - 10 = 230 → clamps to 127.
      expect(
        high
            .apply(const [
              MidiNote(pitch: 10, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        127,
      );
    });

    test('preserves start, duration, velocity, and channel', () {
      const t = InversionTransform(axis: 60, label: 'around C4');
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 0.5,
          duration: 0.75,
          velocity: 0.42,
          channel: 3,
        ),
      ]);
      expect(
        out.single,
        const MidiNote(
          pitch: 56,
          start: 0.5,
          duration: 0.75,
          velocity: 0.42,
          channel: 3,
        ),
      );
    });

    test('copyWith flips active without losing axis/label', () {
      const t = InversionTransform(axis: 60.5, label: 'mirror');
      final flipped = t.copyWith(active: false);
      expect(flipped.axis, 60.5);
      expect(flipped.label, 'mirror');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = InversionTransform(axis: 60, label: 'around C4');
      expect(t.apply(const []), isEmpty);
    });
  });
}
