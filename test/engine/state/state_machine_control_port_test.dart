import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/state/state_machine_control_port.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/engine/state/state_trigger_scheduler.dart';

/// The control plane's `state.fire` seam (issue #233 → behaviour in #244):
/// [StateMachineControlPort] delegates to the scheduler's `fireTo`, ignoring
/// the machine qualifier — v1 has exactly one state machine.
void main() {
  late StateMachineController controller;
  late StateTriggerScheduler scheduler;
  late StateMachineControlPort port;
  late EntityAddress a;
  late EntityAddress b;

  setUp(() {
    controller = StateMachineController();
    scheduler = StateTriggerScheduler(stateMachine: controller);
    controller.onStateEntered = scheduler.onStateEntered;
    port = StateMachineControlPort(scheduler);
    a = controller.addState(name: 'a', position: const Offset(0, 0));
    b = controller.addState(name: 'b', position: const Offset(200, 0));
    controller.connect(a, b);
  });

  tearDown(() {
    scheduler.dispose();
    controller.dispose();
  });

  test('fire routes to the live state\'s transition toward the target', () {
    port.fire(null, 'b');
    expect(controller.activeStateAddress, b);
  });

  test('the machine qualifier is accepted and ignored (v1: one machine)', () {
    port.fire(EntityAddress.parse('state.whatever'), 'b');
    expect(controller.activeStateAddress, b);
  });

  test('an unknown target fires nothing', () {
    port.fire(null, 'nope');
    expect(controller.activeStateAddress, a);
  });
}
