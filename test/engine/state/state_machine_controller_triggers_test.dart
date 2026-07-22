import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/state_machine/state_transition.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_transition_spec.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/engine/state/state_machine_controller.dart';

/// The controller half of issue #244: `setTrigger` as a journaled payload
/// edit, `triggerOf` for the badge/editor, the trigger kind on the rendered
/// transitions, and arming restricted to manual triggers (design §5).
void main() {
  late StateMachineController controller;
  late List<ProjectCommand> recorded;
  late EntityAddress a;
  late EntityAddress b;

  final drum = EntityAddress.parse('domain.drum');

  setUp(() {
    recorded = [];
    controller = StateMachineController(recordCommand: recorded.add);
    a = controller.addState(name: 'a', position: const Offset(0, 0));
    b = controller.addState(name: 'b', position: const Offset(200, 0));
    controller.connect(a, b);
  });

  tearDown(() => controller.dispose());

  StateDocument docOf(EntityAddress address) => controller.documentOf(address)!;

  test('a fresh transition renders with the manual trigger kind', () {
    final transition = controller.transitions.single;
    expect(transition.triggerKind, 'manual');
    expect(controller.triggerOf(a, b), const ManualTrigger());
  });

  test('setTrigger writes the payload as one journaled command and the '
      'rendered kind follows', () {
    recorded.clear();
    final trigger = TimedTrigger(beats: 8, domain: drum);
    expect(controller.setTrigger(a, b, trigger), isTrue);

    expect(recorded, hasLength(1));
    expect(docOf(a).transitions.single.trigger, trigger);
    expect(controller.triggerOf(a, b), trigger);
    expect(controller.transitions.single.triggerKind, 'timed');
  });

  test('setTrigger keeps the transition label', () {
    controller.registry.updateEntityPayload(
      a,
      docOf(a).copyWith(
        transitions: [StateTransitionSpec(to: b, label: 'drop')],
      ),
    );
    controller.setTrigger(a, b, const CodeTrigger());

    final spec = docOf(a).transitions.single;
    expect(spec.label, 'drop');
    expect(spec.trigger, const CodeTrigger());
  });

  test('setTrigger with the stored trigger journals nothing', () {
    recorded.clear();
    expect(controller.setTrigger(a, b, const ManualTrigger()), isTrue);
    expect(recorded, isEmpty);
  });

  test('setTrigger on an unknown transition is refused', () {
    recorded.clear();
    expect(controller.setTrigger(b, a, const CodeTrigger()), isFalse);
    expect(recorded, isEmpty);
  });

  test('a trigger moving away from manual drops the arm', () {
    controller.toggleArmed(StateTransition(source: a, target: b));
    expect(controller.transitions.single.armed, isTrue);

    controller.setTrigger(
      a,
      b,
      const VariableTrigger(name: 'section', value: 'b'),
    );
    expect(controller.transitions.single.armed, isFalse);
  });

  test('toggleArmed refuses to arm a non-manual transition', () {
    controller.setTrigger(a, b, const CodeTrigger());
    controller.toggleArmed(StateTransition(source: a, target: b));
    expect(controller.transitions.single.armed, isFalse);

    // Back to manual: arming works again.
    controller.setTrigger(a, b, const ManualTrigger());
    controller.toggleArmed(StateTransition(source: a, target: b));
    expect(controller.transitions.single.armed, isTrue);
  });

  test('triggerOf is null for an unknown transition', () {
    expect(controller.triggerOf(b, a), isNull);
  });
}
