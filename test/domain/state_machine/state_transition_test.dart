import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';
import 'package:phi/domain/state_machine/state_transition.dart';

void main() {
  group('StateTransition defaults', () {
    test('armed defaults to false; fireOn defaults to "manual"', () {
      const t = StateTransition(
        sourceId: PerformanceStateId('a'),
        targetId: PerformanceStateId('b'),
      );

      expect(t.armed, isFalse);
      expect(t.fireOn, 'manual');
    });
  });

  group('StateTransition.copyWith', () {
    const base = StateTransition(
      sourceId: PerformanceStateId('a'),
      targetId: PerformanceStateId('b'),
    );

    test('preserves equality when only armed / fireOn change', () {
      final next = base.copyWith(armed: true, fireOn: '4 bars');

      expect(next, base);
      expect(next.hashCode, base.hashCode);
    });

    test('replaces only the supplied fields', () {
      final armed = base.copyWith(armed: true);
      expect(armed.armed, isTrue);
      expect(armed.fireOn, 'manual');

      final labelled = base.copyWith(fireOn: '4 bars');
      expect(labelled.armed, isFalse);
      expect(labelled.fireOn, '4 bars');
    });

    test('keeps sourceId / targetId untouched', () {
      final next = base.copyWith(armed: true, fireOn: '4 bars');
      expect(next.sourceId, base.sourceId);
      expect(next.targetId, base.targetId);
    });
  });
}
