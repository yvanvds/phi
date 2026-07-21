import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/always_condition.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  group('AlwaysCondition', () {
    test('is satisfied by any context', () {
      const c = AlwaysCondition();
      expect(c.isSatisfiedBy(const GraphEvalContext.empty()), isTrue);
      expect(
        c.isSatisfiedBy(
          GraphEvalContext(activeState: EntityAddress.parse('state.intro')),
        ),
        isTrue,
      );
      expect(c.label, 'always');
    });

    test('has value equality', () {
      expect(const AlwaysCondition(), const AlwaysCondition());
    });
  });

  group('StateMatchCondition', () {
    final s1 = EntityAddress.parse('state.intro');
    final s2 = EntityAddress.parse('state.break_down');

    test('is satisfied only when its state is live', () {
      final c = StateMatchCondition(s1);
      expect(c.isSatisfiedBy(GraphEvalContext(activeState: s1)), isTrue);
      expect(c.isSatisfiedBy(GraphEvalContext(activeState: s2)), isFalse);
      expect(c.isSatisfiedBy(const GraphEvalContext.empty()), isFalse);
    });

    test('labels with the state leaf name and has value equality', () {
      expect(StateMatchCondition(s1).label, 'state · intro');
      expect(StateMatchCondition(s1), StateMatchCondition(s1));
      expect(StateMatchCondition(s1) == StateMatchCondition(s2), isFalse);
    });
  });

  group('RuntimeVariableCondition', () {
    test('matches the expected value and rejects others', () {
      const c = RuntimeVariableCondition(name: 'mode', expected: 'lead');
      expect(
        c.isSatisfiedBy(const GraphEvalContext(variables: {'mode': 'lead'})),
        isTrue,
      );
      expect(
        c.isSatisfiedBy(const GraphEvalContext(variables: {'mode': 'pad'})),
        isFalse,
      );
      // Unset variable is null, which only matches an expected of null.
      expect(c.isSatisfiedBy(const GraphEvalContext.empty()), isFalse);
    });

    test('an unset variable matches a null expectation', () {
      const c = RuntimeVariableCondition(name: 'mode', expected: null);
      expect(c.isSatisfiedBy(const GraphEvalContext.empty()), isTrue);
    });

    test('labels and has value equality', () {
      expect(
        const RuntimeVariableCondition(name: 'mode', expected: 'lead').label,
        'mode = lead',
      );
      expect(
        const RuntimeVariableCondition(name: 'mode', expected: 'lead'),
        const RuntimeVariableCondition(name: 'mode', expected: 'lead'),
      );
    });
  });
}
