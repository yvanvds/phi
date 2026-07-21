import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  group('GraphEvalContext value equality', () {
    final s1 = EntityAddress.parse('state.intro');
    final s2 = EntityAddress.parse('state.verse');

    test('two contexts with the same live state and vars are equal', () {
      final a = GraphEvalContext(activeState: s1, variables: const {'x': 1});
      final b = GraphEvalContext(activeState: s1, variables: const {'x': 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different live state is not equal', () {
      final a = GraphEvalContext(activeState: s1);
      final b = GraphEvalContext(activeState: s2);
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
