import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/spectral_mapping_transform.dart';

void main() {
  group('SpectralMappingTransform', () {
    test('remaps pitches listed in the table', () {
      const t = SpectralMappingTransform(
        table: {60: 67, 64: 71},
        label: 'stretch',
      );
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        MidiNote(pitch: 64, start: 1, duration: 1, velocity: 1),
      ]);
      expect(out.map((n) => n.pitch), [67, 71]);
    });

    test('passes through pitches absent from the table', () {
      const t = SpectralMappingTransform(table: {60: 72}, label: 'sparse');
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        MidiNote(pitch: 62, start: 1, duration: 1, velocity: 1), // untouched
      ]);
      expect(out.map((n) => n.pitch), [72, 62]);
    });

    test('maps to fractional (microtonal) targets, issue #36', () {
      // Retune the tempered major third onto a just one: 64 → 63.8631.
      const t = SpectralMappingTransform(
        table: {64: 63.8631},
        label: 'just third',
      );
      expect(
        t
            .apply(const [
              MidiNote(pitch: 64, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        closeTo(63.8631, 1e-9),
      );
    });

    test('a fractional input never matches an integer key', () {
      const t = SpectralMappingTransform(table: {60: 72}, label: 'sparse');
      // 60.5 is not the key 60, so it passes through untouched.
      expect(
        t
            .apply(const [
              MidiNote(pitch: 60.5, start: 0, duration: 1, velocity: 1),
            ])
            .single
            .pitch,
        60.5,
      );
    });

    test('an empty table is the identity', () {
      const t = SpectralMappingTransform(table: {}, label: 'noop');
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
      ]);
      expect(out.single.pitch, 60);
    });

    test('clamps mapped values to the 7-bit MIDI range', () {
      const t = SpectralMappingTransform(
        table: {60: 200, 62: -5},
        label: 'loose table',
      );
      final out = t.apply(const [
        MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        MidiNote(pitch: 62, start: 1, duration: 1, velocity: 1),
      ]);
      expect(out.map((n) => n.pitch), [127, 0]);
    });

    test('preserves start, duration, velocity, and channel', () {
      const t = SpectralMappingTransform(table: {60: 65}, label: 'map');
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
          pitch: 65,
          start: 0.5,
          duration: 0.75,
          velocity: 0.42,
          channel: 3,
        ),
      );
    });

    test('copyWith flips active without losing table/label', () {
      const t = SpectralMappingTransform(table: {60: 67}, label: 'map');
      final flipped = t.copyWith(active: false);
      expect(flipped.table, {60: 67});
      expect(flipped.label, 'map');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = SpectralMappingTransform(table: {60: 67}, label: 'map');
      expect(t.apply(const []), isEmpty);
    });
  });
}
