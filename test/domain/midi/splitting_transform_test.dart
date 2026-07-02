import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/transforms/split_voice.dart';
import 'package:phi/domain/midi/transforms/splitting_transform.dart';

void main() {
  group('SplittingTransform', () {
    test('is a voice-family transform', () {
      const t = SplittingTransform(voices: [], label: 'split');
      expect(t.kind, MidiTransformKind.voice);
    });

    test('an empty voice list passes notes through unchanged', () {
      const t = SplittingTransform(voices: [], label: 'split');
      const notes = [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)];

      expect(t.apply(notes), same(notes));
    });

    test('a single default voice is the identity', () {
      const t = SplittingTransform(voices: [SplitVoice()], label: 'split');
      const notes = [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.7, channel: 3),
      ];

      expect(t.apply(notes), notes);
    });

    test('octave doubling keeps the original and adds a layer', () {
      const t = SplittingTransform(
        voices: [SplitVoice(), SplitVoice(pitchOffset: 12, channel: 2)],
        label: 'octave up',
      );
      const source = MidiNote(pitch: 60, start: 2, duration: 1, velocity: 0.8);

      final out = t.apply(const [source]);

      expect(out, hasLength(2));
      expect(out[0], source);
      expect(out[1], source.copyWith(pitch: 72, channel: 2));
    });

    test('copies of one note stay adjacent in the output', () {
      const t = SplittingTransform(
        voices: [SplitVoice(), SplitVoice(pitchOffset: 12)],
        label: 'octave up',
      );
      const notes = [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        MidiNote(pitch: 64, start: 1, duration: 1, velocity: 1),
      ];

      final out = t.apply(notes);

      expect(out.map((n) => n.pitch), [60, 72, 64, 76]);
    });

    test('velocityScale scales and clamps to [0, 1]', () {
      const t = SplittingTransform(
        voices: [SplitVoice(velocityScale: 0.5), SplitVoice(velocityScale: 3)],
        label: 'layers',
      );
      const source = MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.8);

      final out = t.apply(const [source]);

      expect(out[0].velocity, closeTo(0.4, 1e-9));
      expect(out[1].velocity, 1.0);
    });

    test('pitch offsets clamp to the MIDI range', () {
      const t = SplittingTransform(
        voices: [SplitVoice(pitchOffset: 24), SplitVoice(pitchOffset: -24)],
        label: 'extremes',
      );

      final out = t.apply(const [
        MidiNote(pitch: 120, start: 0, duration: 1, velocity: 1),
        MidiNote(pitch: 10, start: 0, duration: 1, velocity: 1),
      ]);

      expect(out.map((n) => n.pitch), [127, 96, 34, 0]);
    });

    test('null channel keeps the source channel, set channel re-routes', () {
      const t = SplittingTransform(
        voices: [SplitVoice(), SplitVoice(channel: 5)],
        label: 'layer to 5',
      );
      const source = MidiNote(
        pitch: 60,
        start: 0,
        duration: 1,
        velocity: 1,
        channel: 2,
      );

      final out = t.apply(const [source]);

      expect(out[0].channel, 2);
      expect(out[1].channel, 5);
    });

    test('copyWith toggles active and keeps the voices', () {
      const t = SplittingTransform(
        voices: [SplitVoice(pitchOffset: 12)],
        label: 'split',
      );

      final off = t.copyWith(active: false);

      expect(off.active, isFalse);
      expect(off.label, t.label);
      expect(off.voices, same(t.voices));
    });
  });
}
