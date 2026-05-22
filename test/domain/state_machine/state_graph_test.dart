import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/state_machine/performance_state.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';
import 'package:phi/domain/state_machine/state_graph.dart';
import 'package:phi/domain/state_machine/state_transition.dart';

PerformanceState _state(String id, {int voice = 1}) => PerformanceState(
  id: PerformanceStateId(id),
  name: 'state $id',
  voice: voice,
  position: Offset.zero,
);

void main() {
  group('StateGraph', () {
    test('addState appends and bumps version + notifies', () {
      final g = StateGraph();
      var ticks = 0;
      g.addListener(() => ticks++);
      final v0 = g.version;

      g.addState(_state('a'));

      expect(g.states, hasLength(1));
      expect(g.version, greaterThan(v0));
      expect(ticks, 1);
    });

    test('removeState also removes touching transitions', () {
      final g = StateGraph();
      g.addState(_state('a'));
      g.addState(_state('b'));
      g.addState(_state('c'));
      g.addTransition(
        const StateTransition(
          sourceId: PerformanceStateId('a'),
          targetId: PerformanceStateId('b'),
        ),
      );
      g.addTransition(
        const StateTransition(
          sourceId: PerformanceStateId('b'),
          targetId: PerformanceStateId('c'),
        ),
      );
      expect(g.transitions, hasLength(2));

      g.removeState(const PerformanceStateId('b'));

      expect(g.states, hasLength(2));
      expect(g.transitions, isEmpty);
    });

    test('removeState on a missing id is a no-op and does not notify', () {
      final g = StateGraph();
      g.addState(_state('a'));
      final v0 = g.version;
      var ticks = 0;
      g.addListener(() => ticks++);

      g.removeState(const PerformanceStateId('missing'));

      expect(g.version, v0);
      expect(ticks, 0);
    });

    test('addTransition rejects self-loops', () {
      final g = StateGraph();
      g.addState(_state('a'));

      final ok = g.addTransition(
        const StateTransition(
          sourceId: PerformanceStateId('a'),
          targetId: PerformanceStateId('a'),
        ),
      );

      expect(ok, isFalse);
      expect(g.transitions, isEmpty);
    });

    test('addTransition rejects duplicates', () {
      final g = StateGraph();
      const t = StateTransition(
        sourceId: PerformanceStateId('a'),
        targetId: PerformanceStateId('b'),
      );

      expect(g.addTransition(t), isTrue);
      expect(g.addTransition(t), isFalse);
      expect(g.transitions, hasLength(1));
    });

    test('removeTransition notifies and bumps version', () {
      final g = StateGraph();
      const t = StateTransition(
        sourceId: PerformanceStateId('a'),
        targetId: PerformanceStateId('b'),
      );
      g.addTransition(t);
      var ticks = 0;
      g.addListener(() => ticks++);

      g.removeTransition(t);

      expect(g.transitions, isEmpty);
      expect(ticks, 1);
    });

    test('beginTransitionDrag / endTransitionDrag toggle the drag source', () {
      final g = StateGraph();
      const src = PerformanceStateId('a');
      g.beginTransitionDrag(src);
      expect(g.dragSourceStateId, src);
      g.endTransitionDrag();
      expect(g.dragSourceStateId, isNull);
    });
  });

  group('PerformanceStateId', () {
    test('value equality + hashCode', () {
      const a = PerformanceStateId('s1');
      const b = PerformanceStateId('s1');
      const c = PerformanceStateId('s2');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('PerformanceStateId.next mints monotonic ids', () {
      final a = PerformanceStateId.next();
      final b = PerformanceStateId.next();

      expect(a, isNot(b));
      expect(a.value, startsWith('s'));
    });
  });

  group('StateTransition equality', () {
    test('same source+target are equal regardless of construction', () {
      const a = StateTransition(
        sourceId: PerformanceStateId('a'),
        targetId: PerformanceStateId('b'),
      );
      const b = StateTransition(
        sourceId: PerformanceStateId('a'),
        targetId: PerformanceStateId('b'),
      );
      const flipped = StateTransition(
        sourceId: PerformanceStateId('b'),
        targetId: PerformanceStateId('a'),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(flipped));
    });
  });
}
