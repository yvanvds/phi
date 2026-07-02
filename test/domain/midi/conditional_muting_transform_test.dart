import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/conditional_muting_transform.dart';

MidiNote _n(int pitch, double start) =>
    MidiNote(pitch: pitch, start: start, duration: 0.25, velocity: 0.7);

void main() {
  group('ConditionalMutingTransform', () {
    test('a predicate that always returns true is the identity', () {
      const t = ConditionalMutingTransform(
        predicate: _alwaysTrue,
        label: 'open',
      );
      final input = [_n(60, 0), _n(62, 1)];
      expect(t.apply(input), input);
    });

    test('a predicate that always returns false mutes everything', () {
      const t = ConditionalMutingTransform(
        predicate: _alwaysFalse,
        label: 'closed',
      );
      expect(t.apply([_n(60, 0), _n(62, 1)]), isEmpty);
    });

    test('gates per note, preserving order of survivors', () {
      const t = ConditionalMutingTransform(
        predicate: _evenPitchOnly,
        label: 'gate',
      );
      final out = t.apply([_n(60, 0), _n(61, 1), _n(62, 2), _n(63, 3)]);
      expect(out.map((n) => n.pitch), [60, 62]);
    });

    test('surviving notes are untouched', () {
      const t = ConditionalMutingTransform(
        predicate: _alwaysTrue,
        label: 'open',
      );
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 2,
          duration: 0.5,
          velocity: 0.42,
          channel: 3,
        ),
      ]);
      expect(out.single.duration, 0.5);
      expect(out.single.velocity, 0.42);
      expect(out.single.channel, 3);
    });

    test('copyWith flips active without losing predicate/label', () {
      const t = ConditionalMutingTransform(
        predicate: _alwaysTrue,
        label: 'gate',
      );
      final flipped = t.copyWith(active: false);
      expect(flipped.predicate, same(_alwaysTrue));
      expect(flipped.label, 'gate');
      expect(flipped.active, isFalse);
    });

    test('returns empty output for empty input', () {
      const t = ConditionalMutingTransform(
        predicate: _alwaysTrue,
        label: 'gate',
      );
      expect(t.apply(const []), isEmpty);
    });
  });
}

bool _alwaysTrue(MidiNote note) => true;

bool _alwaysFalse(MidiNote note) => false;

bool _evenPitchOnly(MidiNote note) => note.pitch.isEven;
