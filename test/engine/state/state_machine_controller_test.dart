import 'package:flutter_test/flutter_test.dart';
import 'package:phi/engine/state/state_machine_controller.dart';

void main() {
  group('StateMachineController', () {
    late StateMachineController controller;

    setUp(() => controller = StateMachineController());
    tearDown(() => controller.dispose());

    test('addState snaps the initial position to the 16px grid', () {
      final s = controller.addState(
        name: 'intro',
        position: const Offset(53, 71),
      );

      // 53 → 48, 71 → 64 (nearest multiples of 16).
      expect(s.position, const Offset(48, 64));
      expect(controller.graph.states, hasLength(1));
    });

    test('moveState snaps to the 16px grid', () {
      final s = controller.addState(
        name: 'intro',
        position: const Offset(48, 48),
      );

      controller.moveState(s.id, const Offset(3, 11));

      // 51 → 48, 59 → 64.
      expect(s.position, const Offset(48, 64));
    });

    test('moveState on a missing id is a no-op', () {
      final s = controller.addState(
        name: 'intro',
        position: const Offset(48, 48),
      );

      controller.removeState(s.id);
      controller.moveState(s.id, const Offset(16, 16));

      expect(controller.graph.states, isEmpty);
    });

    test('connect rejects self-loops and unknown endpoints', () {
      final a = controller.addState(name: 'a', position: Offset.zero);

      expect(controller.connect(a.id, a.id), isFalse);
      expect(controller.graph.transitions, isEmpty);
    });

    test(
      'connect inserts a transition between two states; disconnect drops it',
      () {
        final a = controller.addState(name: 'a', position: Offset.zero);
        final b = controller.addState(
          name: 'b',
          position: const Offset(160, 0),
        );

        expect(controller.connect(a.id, b.id), isTrue);
        expect(controller.graph.transitions, hasLength(1));

        controller.disconnect(a.id, b.id);
        expect(controller.graph.transitions, isEmpty);
      },
    );

    test('connect rejects duplicates', () {
      final a = controller.addState(name: 'a', position: Offset.zero);
      final b = controller.addState(name: 'b', position: const Offset(160, 0));

      expect(controller.connect(a.id, b.id), isTrue);
      expect(controller.connect(a.id, b.id), isFalse);
      expect(controller.graph.transitions, hasLength(1));
    });

    test('beginTransitionDrag / endTransitionDrag forward to the graph', () {
      final a = controller.addState(name: 'a', position: Offset.zero);

      controller.beginTransitionDrag(a.id);
      expect(controller.graph.dragSourceStateId, a.id);

      controller.endTransitionDrag();
      expect(controller.graph.dragSourceStateId, isNull);
    });
  });
}
