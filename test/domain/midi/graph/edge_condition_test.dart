import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/always_condition.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';

void main() {
  group('AlwaysCondition', () {
    test('is satisfied by any context', () {
      const c = AlwaysCondition();
      expect(c.isSatisfiedBy(const GraphEvalContext.empty()), isTrue);
      expect(
        c.isSatisfiedBy(
          const GraphEvalContext(activeStateId: PerformanceStateId('s')),
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
    const s1 = PerformanceStateId('s1');
    const s2 = PerformanceStateId('s2');

    test('is satisfied only when its state is live', () {
      const c = StateMatchCondition(s1);
      expect(
        c.isSatisfiedBy(const GraphEvalContext(activeStateId: s1)),
        isTrue,
      );
      expect(
        c.isSatisfiedBy(const GraphEvalContext(activeStateId: s2)),
        isFalse,
      );
      expect(c.isSatisfiedBy(const GraphEvalContext.empty()), isFalse);
    });

    test('labels with the state id and has value equality', () {
      expect(const StateMatchCondition(s1).label, 'state · s1');
      expect(const StateMatchCondition(s1), const StateMatchCondition(s1));
      expect(
        const StateMatchCondition(s1) == const StateMatchCondition(s2),
        isFalse,
      );
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
