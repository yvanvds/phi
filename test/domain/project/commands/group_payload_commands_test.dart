import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/create_group_command.dart';
import 'package:phi/domain/project/commands/update_group_payload_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

/// The command layer for kind-declared group payloads (issue #165): a group bus
/// is created and edited through journalable [CreateGroupCommand] /
/// [UpdateGroupPayloadCommand]s, so its state is dirty-tracked and recoverable
/// like any entity's.
void main() {
  late ProjectRegistry registry;

  setUp(() => registry = ProjectRegistry());
  tearDown(() => registry.dispose());

  group('CreateGroupCommand with a payload', () {
    test('apply creates the group with its payload and indexed sends', () {
      registry.createEntity(addr('mix.verb'));
      final command = CreateGroupCommand(
        registry,
        addr('mix.drums'),
        payload: const {'name': 'drums', 'volume': 0.5},
        references: {addr('mix.verb')},
      );

      command.apply();

      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'drums',
        'volume': 0.5,
      });
      expect(registry.referrersOf(addr('mix.verb')), {addr('mix.drums')});
    });

    test('revert removes the group it created', () {
      final command = CreateGroupCommand(
        registry,
        addr('mix.drums'),
        payload: const {'name': 'drums'},
      )..apply();
      expect(registry.groupAt(addr('mix.drums')), isNotNull);

      command.revert();
      expect(registry.groupAt(addr('mix.drums')), isNull);
    });

    test('toJson carries the payload and references', () {
      final json = CreateGroupCommand(
        registry,
        addr('mix.drums'),
        payload: const {'name': 'drums'},
        references: {addr('mix.verb')},
      ).toJson();

      expect(json['type'], 'create_group');
      expect(json['address'], 'mix.drums');
      expect(json['payload'], const {'name': 'drums'});
      expect(json['references'], ['mix.verb']);
    });

    test('a bare create omits payload and references from toJson', () {
      final json = CreateGroupCommand(registry, addr('mix.drums')).toJson();
      expect(json.containsKey('payload'), isFalse);
      expect(json.containsKey('references'), isFalse);
    });
  });

  group('UpdateGroupPayloadCommand', () {
    test('apply replaces the payload; revert restores the previous one', () {
      registry.createGroup(
        addr('mix.drums'),
        payload: const {'name': 'drums', 'volume': 1.0},
      );

      final command = UpdateGroupPayloadCommand(
        registry,
        addr('mix.drums'),
        const {'name': 'drums', 'volume': 0.25},
      )..apply();

      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'drums',
        'volume': 0.25,
      });

      command.revert();
      expect(registry.groupAt(addr('mix.drums'))!.payload, const {
        'name': 'drums',
        'volume': 1.0,
      });
    });

    test('entitiesTouched is the group address for dirty tracking', () {
      final command = UpdateGroupPayloadCommand(
        registry,
        addr('mix.drums'),
        const {'volume': 0.1},
      );
      expect(command.entitiesTouched, {addr('mix.drums')});
    });

    test('toJson carries the new payload verbatim', () {
      final json = UpdateGroupPayloadCommand(
        registry,
        addr('mix.drums'),
        const {'volume': 0.1},
      ).toJson();

      expect(json['type'], 'update_group_payload');
      expect(json['address'], 'mix.drums');
      expect(json['payload'], const {'volume': 0.1});
    });
  });
}
