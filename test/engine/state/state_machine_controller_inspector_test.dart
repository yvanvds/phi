import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/state_machine/store/state_document.dart';
import 'package:phi/domain/state_machine/store/state_trigger.dart';
import 'package:phi/engine/state/state_machine_controller.dart';

/// The controller half of issue #245: `setOnEnter` and `setTransitionLabel`
/// as journaled payload edits the inspector's ON ENTER picker and
/// TRANSITIONS rows drive.
void main() {
  late StateMachineController controller;
  late List<ProjectCommand> recorded;
  late EntityAddress a;
  late EntityAddress b;

  final script = EntityAddress.parse('code.scratch');

  setUp(() {
    recorded = [];
    controller = StateMachineController(recordCommand: recorded.add);
    a = controller.addState(name: 'a', position: const Offset(0, 0));
    b = controller.addState(name: 'b', position: const Offset(200, 0));
    controller.connect(a, b);
    controller.registry.createEntity(
      EntityAddress(kind: RegistryKinds.code, segments: const ['scratch']),
      payload: const {'source': ''},
    );
    recorded.clear();
  });

  tearDown(() => controller.dispose());

  StateDocument docOf(EntityAddress address) => controller.documentOf(address)!;

  group('setOnEnter', () {
    test('writes the script as one journaled payload update', () {
      expect(controller.setOnEnter(a, script), isTrue);

      expect(recorded, hasLength(1));
      expect(docOf(a).onEnter, script);
    });

    test('declares the reference so delete-impact lists the state', () {
      controller.setOnEnter(a, script);
      final impact = controller.registry.impactOfRemoving(script);
      expect(impact.referrers, contains(a));
    });

    test('clears with null as one journaled command', () {
      controller.setOnEnter(a, script);
      recorded.clear();

      expect(controller.setOnEnter(a, null), isTrue);
      expect(recorded, hasLength(1));
      expect(docOf(a).onEnter, isNull);
    });

    test('the stored script journals nothing', () {
      controller.setOnEnter(a, script);
      recorded.clear();

      expect(controller.setOnEnter(a, script), isTrue);
      expect(recorded, isEmpty);

      // Clearing an already-unset script is equally a no-op.
      controller.setOnEnter(a, null);
      recorded.clear();
      expect(controller.setOnEnter(a, null), isTrue);
      expect(recorded, isEmpty);
    });

    test('an unknown state is refused', () {
      expect(
        controller.setOnEnter(EntityAddress.parse('state.ghost'), script),
        isFalse,
      );
      expect(recorded, isEmpty);
    });
  });

  group('setTransitionLabel', () {
    test('writes the label as one journaled payload update', () {
      expect(controller.setTransitionLabel(a, b, 'drop'), isTrue);

      expect(recorded, hasLength(1));
      expect(docOf(a).transitions.single.label, 'drop');
    });

    test('trims whitespace and keeps the trigger', () {
      controller.setTrigger(a, b, const CodeTrigger());
      recorded.clear();

      controller.setTransitionLabel(a, b, '  drop  ');
      final spec = docOf(a).transitions.single;
      expect(spec.label, 'drop');
      expect(spec.trigger, const CodeTrigger());
    });

    test('blank clears the label back to unset', () {
      controller.setTransitionLabel(a, b, 'drop');
      recorded.clear();

      expect(controller.setTransitionLabel(a, b, '   '), isTrue);
      expect(recorded, hasLength(1));
      expect(docOf(a).transitions.single.label, isNull);
    });

    test('the stored label journals nothing', () {
      controller.setTransitionLabel(a, b, 'drop');
      recorded.clear();

      expect(controller.setTransitionLabel(a, b, 'drop'), isTrue);
      expect(recorded, isEmpty);

      // Clearing an already-unset label is equally a no-op.
      controller.setTransitionLabel(a, b, null);
      recorded.clear();
      expect(controller.setTransitionLabel(a, b, null), isTrue);
      expect(recorded, isEmpty);
    });

    test('an unknown transition or source is refused', () {
      expect(controller.setTransitionLabel(b, a, 'drop'), isFalse);
      expect(
        controller.setTransitionLabel(
          EntityAddress.parse('state.ghost'),
          b,
          'drop',
        ),
        isFalse,
      );
      expect(recorded, isEmpty);
    });
  });
}
