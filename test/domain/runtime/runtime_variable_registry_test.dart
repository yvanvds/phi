import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';

void main() {
  late RuntimeVariableRegistry registry;
  var notifications = 0;

  setUp(() {
    registry = RuntimeVariableRegistry();
    notifications = 0;
    registry.addListener(() => notifications++);
  });

  tearDown(() => registry.dispose());

  group('define', () {
    test('adds a variable and notifies', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      expect(registry.contains('mode'), isTrue);
      expect(registry.byName('mode')!.values, ['lead', 'pad']);
      expect(registry.byName('mode')!.current, 'lead');
      expect(notifications, 1);
      expect(registry.version, 1);
    });

    test('redefine keeps the current value when it is still a candidate', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      registry.setValue('mode', 'pad');
      registry.define(name: 'mode', values: ['pad', 'bass']);
      expect(registry.byName('mode')!.current, 'pad');
    });

    test('redefine resets the current value when it is dropped', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      registry.setValue('mode', 'pad');
      registry.define(name: 'mode', values: ['lead', 'bass']);
      expect(registry.byName('mode')!.current, 'lead');
    });
  });

  group('setValue', () {
    test('moves the live value and notifies', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      notifications = 0;
      expect(registry.setValue('mode', 'pad'), isTrue);
      expect(registry.byName('mode')!.current, 'pad');
      expect(notifications, 1);
    });

    test('is a no-op for an unknown variable', () {
      expect(registry.setValue('ghost', 'x'), isFalse);
      expect(notifications, 0);
    });

    test('is a no-op for a non-candidate value', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      notifications = 0;
      expect(registry.setValue('mode', 'bass'), isFalse);
      expect(notifications, 0);
    });

    test('is a no-op — and no notify — when already at that value', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      notifications = 0;
      expect(registry.setValue('mode', 'lead'), isFalse);
      expect(notifications, 0);
    });
  });

  group('remove', () {
    test('drops a variable and notifies', () {
      registry.define(name: 'mode', values: ['lead']);
      notifications = 0;
      registry.remove('mode');
      expect(registry.contains('mode'), isFalse);
      expect(notifications, 1);
    });

    test('is a no-op for an unknown variable', () {
      registry.remove('ghost');
      expect(notifications, 0);
    });
  });

  group('snapshot', () {
    test('maps each variable name to its current value', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      registry.define(name: 'intensity', values: ['low', 'high']);
      registry.setValue('intensity', 'high');
      expect(registry.snapshot(), {'mode': 'lead', 'intensity': 'high'});
    });

    test('feeds a context that opens the matching guard', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      const guard = RuntimeVariableCondition(name: 'mode', expected: 'pad');

      final closed = GraphEvalContext(variables: registry.snapshot());
      expect(guard.isSatisfiedBy(closed), isFalse);

      registry.setValue('mode', 'pad');
      final open = GraphEvalContext(variables: registry.snapshot());
      expect(guard.isSatisfiedBy(open), isTrue);
    });

    test('is detached — a later mutation does not change a taken snapshot', () {
      registry.define(name: 'mode', values: ['lead', 'pad']);
      final snap = registry.snapshot();
      registry.setValue('mode', 'pad');
      expect(snap['mode'], 'lead');
    });
  });
}
