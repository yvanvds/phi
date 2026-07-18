import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/update_entity_payload_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_error.dart';
import 'package:phi/domain/project/registry_exception.dart';

void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  group('ProjectRegistry.updateEntityPayload', () {
    test('replaces the payload in place, keeping name + position', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(addr('clip.phrase_a'), payload: {'v': 1});

      registry.updateEntityPayload(addr('clip.phrase_a'), {'v': 2});

      final entity = registry.entityAt(addr('clip.phrase_a'))!;
      expect(entity.name, 'phrase_a');
      expect(entity.payload, {'v': 2});
    });

    test('notifies listeners', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(addr('clip.phrase_a'), payload: {'v': 1});
      var notified = 0;
      registry.addListener(() => notified++);

      registry.updateEntityPayload(addr('clip.phrase_a'), {'v': 2});

      expect(notified, 1);
    });

    test('emits no structural lifecycle event (payload is not namespace)', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(addr('clip.phrase_a'), payload: {'v': 1});
      final events = <Object>[];
      final sub = registry.events.listen(events.add);
      addTearDown(sub.cancel);

      registry.updateEntityPayload(addr('clip.phrase_a'), {'v': 2});

      expect(events, isEmpty);
    });

    test('throws notFound when no entity is there', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      expect(
        () => registry.updateEntityPayload(addr('clip.gone'), {'v': 2}),
        throwsA(
          isA<RegistryException>().having(
            (e) => e.error,
            'error',
            RegistryError.notFound,
          ),
        ),
      );
    });
  });

  group('UpdateEntityPayloadCommand', () {
    test('apply sets the new payload; revert restores the old one', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(addr('clip.phrase_a'), payload: {'v': 1});

      final command = UpdateEntityPayloadCommand(
        registry,
        addr('clip.phrase_a'),
        {'v': 2},
      );

      command.apply();
      expect(registry.entityAt(addr('clip.phrase_a'))!.payload, {'v': 2});

      command.revert();
      expect(registry.entityAt(addr('clip.phrase_a'))!.payload, {'v': 1});
    });

    test('touches exactly the target entity', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(addr('clip.phrase_a'), payload: {'v': 1});
      final command = UpdateEntityPayloadCommand(
        registry,
        addr('clip.phrase_a'),
        {'v': 2},
      );
      expect(command.entitiesTouched, {addr('clip.phrase_a')});
    });

    test('toJson is JSON-shaped for the journal', () {
      final registry = ProjectRegistry();
      addTearDown(registry.dispose);
      registry.createEntity(addr('clip.phrase_a'), payload: {'v': 1});
      final json = UpdateEntityPayloadCommand(registry, addr('clip.phrase_a'), {
        'v': 2,
      }).toJson();
      expect(json['type'], 'update_payload');
      expect(json['address'], 'clip.phrase_a');
      expect(json['payload'], {'v': 2});
    });
  });
}
