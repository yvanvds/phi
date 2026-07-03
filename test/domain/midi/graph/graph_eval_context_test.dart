import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';

void main() {
  group('GraphEvalContext value equality', () {
    const s1 = PerformanceStateId('s1');
    const s2 = PerformanceStateId('s2');

    test('two contexts with the same live state and vars are equal', () {
      const a = GraphEvalContext(activeStateId: s1, variables: {'x': 1});
      const b = GraphEvalContext(activeStateId: s1, variables: {'x': 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different live state is not equal', () {
      const a = GraphEvalContext(activeStateId: s1);
      const b = GraphEvalContext(activeStateId: s2);
      expect(a, isNot(b));
    });

    test('a different variable value is not equal', () {
      const a = GraphEvalContext(variables: {'x': 1});
      const b = GraphEvalContext(variables: {'x': 2});
      expect(a, isNot(b));
    });

    test('the empty context equals an all-null default', () {
      expect(const GraphEvalContext.empty(), const GraphEvalContext());
    });
  });
}
