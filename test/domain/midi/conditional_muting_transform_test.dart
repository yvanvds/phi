import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/conditional_muting_transform.dart';
import 'package:phi/domain/midi/transforms/note_comparison.dart';
import 'package:phi/domain/midi/transforms/note_condition.dart';
import 'package:phi/domain/midi/transforms/note_field.dart';

MidiNote _n(double pitch, double start, {double velocity = 0.7}) =>
    MidiNote(pitch: pitch, start: start, duration: 0.25, velocity: velocity);

/// Mute notes softer than 0.5.
const _muteSoft = NoteFieldCondition(
  field: NoteField.velocity,
  comparison: NoteComparison.lessThan,
  threshold: 0.5,
);

void main() {
  group('ConditionalMutingTransform', () {
    test('the empty keep-all default mutes nothing', () {
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'mute · if',
      );
      final input = [_n(60, 0), _n(62, 1)];
      expect(t.apply(input), input);
    });

    test('a matching condition mutes the notes it matches', () {
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup(conditions: [_muteSoft]),
        label: 'mute soft',
      );
      final out = t.apply([
        _n(60, 0, velocity: 0.7),
        _n(62, 1, velocity: 0.3),
        _n(64, 2, velocity: 0.9),
        _n(66, 3, velocity: 0.2),
      ]);
      // Only the loud notes survive, in order.
      expect(out.map((n) => n.pitch), [60, 64]);
    });

    test('an all-group mutes only notes matching every child', () {
      const high = NoteFieldCondition(
        field: NoteField.pitch,
        comparison: NoteComparison.greaterOrEqual,
        threshold: 64,
      );
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup(
          combinator: NoteConditionCombinator.all,
          conditions: [_muteSoft, high],
        ),
        label: 'mute soft highs',
      );
      final out = t.apply([
        _n(66, 0, velocity: 0.2), // soft AND high → muted
        _n(66, 1, velocity: 0.9), // high but loud → kept
        _n(60, 2, velocity: 0.2), // soft but low → kept
      ]);
      expect(out.map((n) => n.pitch), [66, 60]);
    });

    test('surviving notes are untouched', () {
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'open',
      );
      final out = t.apply(const [
        MidiNote(
          pitch: 64,
          start: 2,
          duration: 0.5,
          velocity: 0.42,
          voice: 'voice.a',
        ),
      ]);
      expect(out.single.duration, 0.5);
      expect(out.single.velocity, 0.42);
      expect(out.single.voice, 'voice.a');
    });

    test('predicate is the evaluated keep-form of the condition', () {
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup(conditions: [_muteSoft]),
        label: 'mute soft',
      );
      // A soft note matches the mute condition, so the keep-predicate drops it.
      expect(t.predicate(_n(60, 0, velocity: 0.2)), isFalse);
      expect(t.predicate(_n(60, 0, velocity: 0.9)), isTrue);
    });

    test('copyWith flips active without losing condition/label', () {
      const condition = NoteConditionGroup(conditions: [_muteSoft]);
      const t = ConditionalMutingTransform(condition: condition, label: 'gate');
      final flipped = t.copyWith(active: false);
      expect(flipped.condition, condition);
      expect(flipped.label, 'gate');
      expect(flipped.active, isFalse);
    });

    test('copyWith replaces the condition in place', () {
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'gate',
      );
      const next = NoteConditionGroup(conditions: [_muteSoft]);
      final edited = t.copyWith(condition: next);
      expect(edited.condition, next);
      expect(edited.label, 'gate');
      expect(edited.active, isTrue);
    });

    test('returns empty output for empty input', () {
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'gate',
      );
      expect(t.apply(const []), isEmpty);
    });
  });
}
