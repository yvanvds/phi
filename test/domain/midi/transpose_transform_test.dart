import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';

void main() {
  group('TransposeTransform', () {
    test('shifts every pitch by the configured semitones', () {
      const t = TransposeTransform(semitones: 7, label: 'up a fifth');
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.8),
        MidiNote(pitch: 64, start: 1, duration: 1, velocity: 0.5),
      ]);
      expect(out.map((n) => n.pitch), [67, 71]);
    });

    test('clamps to the 7-bit MIDI range rather than wrapping', () {
      const high = TransposeTransform(semitones: 60, label: '+60');
      const low = TransposeTransform(semitones: -120, label: '-120');
      expect(
        high
            .apply(const [
              MidiNote(pitch: 100, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        127,
      );
      expect(
        low
            .apply(const [
              MidiNote(pitch: 10, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        0,
      );
    });

    test('preserves start, duration, velocity, and channel', () {
      const t = TransposeTransform(semitones: 2, label: '+2');
      final out = t.apply(const [
        MidiNote(
          pitch: 60,
          start: 0.5,
          duration: 0.75,
          velocity: 0.42,
          channel: 3,
        ),
      ]);
      expect(
        out.single,
        const MidiNote(
          pitch: 62,
          start: 0.5,
          duration: 0.75,
          velocity: 0.42,
          channel: 3,
        ),
      );
    });

    test('returns empty output for empty input', () {
      const t = TransposeTransform(semitones: 5, label: '+5');
      expect(t.apply(const []), isEmpty);
    });
  });
}
