import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/create_group_command.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/commands/remove_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/recovery/registry_command_codec.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  const codec = RegistryCommandCodec();

  test('decoded create_entity replays payload and references', () {
    // The command as it was journaled on the original registry.
    final journaled = CreateEntityCommand(
      ProjectRegistry(),
      addr('voice.bells'),
      payload: {'gain': 0.5},
      references: {addr('mix.perc')},
    ).toJson();

    // Replay it onto a fresh registry — the recovery path.
    final registry = ProjectRegistry();
    codec.decode(journaled, registry).apply();

    expect(registry.entityAt(addr('voice.bells'))!.payload, {'gain': 0.5});
    expect(registry.referencesOf(addr('voice.bells')), {addr('mix.perc')});
    expect(registry.referrersOf(addr('mix.perc')), {addr('voice.bells')});
  });

  test('decoded create_entity without payload or references replays a '
      'bare entity', () {
    final journaled = CreateEntityCommand(
      ProjectRegistry(),
      addr('clip.lead_line'),
    ).toJson();

    final registry = ProjectRegistry();
    codec.decode(journaled, registry).apply();

    final entity = registry.entityAt(addr('clip.lead_line'));
    expect(entity, isNotNull);
    expect(entity!.payload, isNull);
    expect(entity.references, isEmpty);
  });

  test('decoded create_group replays the group', () {
    final journaled = CreateGroupCommand(
      ProjectRegistry(),
      addr('clip.drums'),
    ).toJson();

    final registry = ProjectRegistry();
    codec.decode(journaled, registry).apply();

    expect(registry.groupAt(addr('clip.drums')), isNotNull);
  });

  test('decoded move replays the relocation and refactor', () {
    // Original: an entity that a referent points at, then a rename.
    final original = ProjectRegistry();
    original.createEntity(addr('mix.perc'));
    original.createEntity(addr('voice.bells'), references: {addr('mix.perc')});
    final journaled = MoveEntityCommand(
      original,
      addr('mix.perc'),
      addr('mix.percussion'),
    ).toJson();

    // Replay onto a fresh registry seeded to the pre-move state.
    final registry = ProjectRegistry();
    registry.createEntity(addr('mix.perc'));
    registry.createEntity(addr('voice.bells'), references: {addr('mix.perc')});
    codec.decode(journaled, registry).apply();

    expect(registry.entityAt(addr('mix.perc')), isNull);
    expect(registry.entityAt(addr('mix.percussion')), isNotNull);
    // Rename = refactor: the referent followed the address.
    expect(registry.referencesOf(addr('voice.bells')), {
      addr('mix.percussion'),
    });
  });

  test('decoded remove_entity replays the deletion', () {
    final journaled = RemoveEntityCommand(
      ProjectRegistry(),
      addr('clip.a'),
    ).toJson();

    final registry = ProjectRegistry();
    registry.createEntity(addr('clip.a'));
    codec.decode(journaled, registry).apply();

    expect(registry.entityAt(addr('clip.a')), isNull);
  });

  test('an unknown command type throws a FormatException', () {
    expect(
      () => codec.decode({'type': 'frobnicate'}, ProjectRegistry()),
      throwsFormatException,
    );
  });

  test('a missing address field throws a FormatException', () {
    expect(
      () => codec.decode({'type': 'create_entity'}, ProjectRegistry()),
      throwsFormatException,
    );
  });
}
