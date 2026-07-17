import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/transforms/note_comparison.dart';
import 'package:phi/domain/midi/transforms/note_condition.dart';
import 'package:phi/domain/midi/transforms/note_field.dart';

MidiNote _note({
  double pitch = 60,
  double velocity = 0.7,
  int channel = 0,
  double start = 0,
}) => MidiNote(
  pitch: pitch,
  start: start,
  duration: 0.25,
  velocity: velocity,
  channel: channel,
);

void main() {
  group('NoteField.read', () {
    test('reads each field, widening channel to a double', () {
      final note = _note(pitch: 64, velocity: 0.4, channel: 3, start: 1.5);
      expect(NoteField.pitch.read(note), 64);
      expect(NoteField.velocity.read(note), 0.4);
      expect(NoteField.channel.read(note), 3.0);
      expect(NoteField.start.read(note), 1.5);
    });
  });

  group('NoteComparison.test', () {
    test('each operator relates value to threshold', () {
      expect(NoteComparison.lessThan.test(1, 2), isTrue);
      expect(NoteComparison.lessThan.test(2, 2), isFalse);
      expect(NoteComparison.lessOrEqual.test(2, 2), isTrue);
      expect(NoteComparison.equal.test(2, 2), isTrue);
      expect(NoteComparison.equal.test(2, 3), isFalse);
      expect(NoteComparison.notEqual.test(2, 3), isTrue);
      expect(NoteComparison.greaterOrEqual.test(2, 2), isTrue);
      expect(NoteComparison.greaterThan.test(3, 2), isTrue);
      expect(NoteComparison.greaterThan.test(2, 2), isFalse);
    });
  });

  group('NoteFieldCondition', () {
    test('matches on the chosen field and comparison', () {
      const soft = NoteFieldCondition(
        field: NoteField.velocity,
        comparison: NoteComparison.lessThan,
        threshold: 0.5,
      );
      expect(soft.matches(_note(velocity: 0.4)), isTrue);
      expect(soft.matches(_note(velocity: 0.5)), isFalse);
      expect(soft.matches(_note(velocity: 0.9)), isFalse);
    });

    test('gates on pitch, channel, and start too', () {
      const top = NoteFieldCondition(
        field: NoteField.pitch,
        comparison: NoteComparison.greaterOrEqual,
        threshold: 72,
      );
      expect(top.matches(_note(pitch: 72)), isTrue);
      expect(top.matches(_note(pitch: 71)), isFalse);

      const onChannel = NoteFieldCondition(
        field: NoteField.channel,
        comparison: NoteComparison.equal,
        threshold: 2,
      );
      expect(onChannel.matches(_note(channel: 2)), isTrue);
      expect(onChannel.matches(_note(channel: 1)), isFalse);

      const late = NoteFieldCondition(
        field: NoteField.start,
        comparison: NoteComparison.greaterThan,
        threshold: 1,
      );
      expect(late.matches(_note(start: 2)), isTrue);
      expect(late.matches(_note(start: 0.5)), isFalse);
    });

    test('copyWith replaces only the named fields', () {
      const base = NoteFieldCondition(
        field: NoteField.velocity,
        comparison: NoteComparison.lessThan,
        threshold: 0.5,
      );
      final next = base.copyWith(field: NoteField.pitch, threshold: 60);
      expect(next.field, NoteField.pitch);
      expect(next.comparison, base.comparison);
      expect(next.threshold, 60);
    });

    test('value equality and hashCode', () {
      const a = NoteFieldCondition(
        field: NoteField.pitch,
        comparison: NoteComparison.greaterThan,
        threshold: 60,
      );
      const b = NoteFieldCondition(
        field: NoteField.pitch,
        comparison: NoteComparison.greaterThan,
        threshold: 60,
      );
      const c = NoteFieldCondition(
        field: NoteField.pitch,
        comparison: NoteComparison.greaterThan,
        threshold: 61,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('NoteConditionGroup', () {
    const soft = NoteFieldCondition(
      field: NoteField.velocity,
      comparison: NoteComparison.lessThan,
      threshold: 0.5,
    );
    const high = NoteFieldCondition(
      field: NoteField.pitch,
      comparison: NoteComparison.greaterOrEqual,
      threshold: 72,
    );

    test('empty any group matches nothing (the keep-all default)', () {
      const group = NoteConditionGroup.empty();
      expect(group.combinator, NoteConditionCombinator.any);
      expect(group.matches(_note(velocity: 0.1, pitch: 100)), isFalse);
      expect(group.matches(_note(velocity: 0.9, pitch: 40)), isFalse);
    });

    test('empty all group matches everything (vacuous truth)', () {
      const group = NoteConditionGroup(combinator: NoteConditionCombinator.all);
      expect(group.matches(_note()), isTrue);
    });

    test('any matches when at least one child matches', () {
      const group = NoteConditionGroup(conditions: [soft, high]);
      expect(group.matches(_note(velocity: 0.4, pitch: 40)), isTrue); // soft
      expect(group.matches(_note(velocity: 0.9, pitch: 80)), isTrue); // high
      expect(
        group.matches(_note(velocity: 0.9, pitch: 40)),
        isFalse,
      ); // neither
    });

    test('all matches only when every child matches', () {
      const group = NoteConditionGroup(
        combinator: NoteConditionCombinator.all,
        conditions: [soft, high],
      );
      expect(group.matches(_note(velocity: 0.4, pitch: 80)), isTrue); // both
      expect(group.matches(_note(velocity: 0.4, pitch: 40)), isFalse); // one
    });

    test('copyWith replaces only the named fields', () {
      const base = NoteConditionGroup(conditions: [soft]);
      final next = base.copyWith(combinator: NoteConditionCombinator.all);
      expect(next.combinator, NoteConditionCombinator.all);
      expect(next.conditions, [soft]);
    });

    test('value equality is element-wise over the children', () {
      const a = NoteConditionGroup(conditions: [soft, high]);
      const b = NoteConditionGroup(conditions: [soft, high]);
      const c = NoteConditionGroup(conditions: [soft]);
      const d = NoteConditionGroup(
        combinator: NoteConditionCombinator.all,
        conditions: [soft, high],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('groups nest — a group can hold another group', () {
      const nested = NoteConditionGroup(
        combinator: NoteConditionCombinator.all,
        conditions: [
          soft,
          NoteConditionGroup(conditions: [high]),
        ],
      );
      // soft AND (any of {high}) → both must hold.
      expect(nested.matches(_note(velocity: 0.4, pitch: 80)), isTrue);
      expect(nested.matches(_note(velocity: 0.4, pitch: 40)), isFalse);
    });
  });
}
