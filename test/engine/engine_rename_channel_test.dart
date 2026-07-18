import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/commands/update_entity_payload_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// Renaming a user channel (issue #141): the engine updates the strip's display
/// name in its `mix.` payload and, when the new name slugs to a new address,
/// **moves** the entity so the address follows the name (design §4, rename =
/// refactor). The move rematerialises the channel — its live volume/mute/solo
/// ride the payload and survive — and the change is journaled (payload update +
/// move) for dirty-tracking and recovery.
void main() {
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  MixStrip stripAt(ProjectRegistry registry, EntityAddress address) =>
      MixStrip.fromJson((registry.entityAt(address)!.payload! as Map).cast());

  late FakeYseGateway gateway;
  late PhiEngine engine;
  late ProjectRegistry registry;
  late List<ProjectCommand> recorded;

  setUp(() {
    gateway = FakeYseGateway();
    engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    registry = ProjectRegistry();
    recorded = <ProjectCommand>[];
    engine.start();
    engine.bindProject(registry, recordCommand: recorded.add);
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
    registry.dispose();
  });

  test('renames the display name and moves the address to the new slug', () {
    engine.addChannel(name: 'drums');
    recorded.clear();

    engine.renameChannel(engine.channels.value.single, 'lead synth');

    // The entity moved to the slug of the new name …
    expect(registry.contains(mix('drums')), isFalse);
    expect(registry.contains(mix('lead_synth')), isTrue);
    // … carrying the new display name in its payload …
    expect(stripAt(registry, mix('lead_synth')).name, 'lead synth');
    // … and the materialised channel reflects it.
    expect(engine.channels.value.single.name, 'lead synth');
    // A live gateway channel exists under the new name.
    expect(gateway.channels.values.map((c) => c.name), contains('lead synth'));
  });

  test('records a payload update then a move (both journal-encodable)', () {
    engine.addChannel(name: 'drums');
    recorded.clear();

    engine.renameChannel(engine.channels.value.single, 'bass');

    expect(recorded, hasLength(2));
    expect(recorded[0], isA<UpdateEntityPayloadCommand>());
    expect(recorded[1], isA<MoveEntityCommand>());
    expect(recorded[0].toJson()['type'], 'update_payload');
    final moveJson = recorded[1].toJson();
    expect(moveJson['type'], 'move');
    expect(moveJson['from'], 'mix.drums');
    expect(moveJson['to'], 'mix.bass');
  });

  test('the rename preserves live volume, mute and solo', () {
    final ch = engine.addChannel(name: 'drums');
    engine.setChannelVolume(ch, 0.42);
    engine.setChannelMuted(ch, muted: true);
    engine.setChannelSoloed(ch, soloed: true);
    recorded.clear();

    engine.renameChannel(engine.channels.value.single, 'kick');

    final renamed = engine.channels.value.single;
    expect(renamed.name, 'kick');
    expect(renamed.volume, closeTo(0.42, 1e-9));
    expect(renamed.muted, isTrue);
    expect(renamed.soloed, isTrue);
    // Persisted alongside the new name, so a reload restores them too.
    final strip = stripAt(registry, mix('kick'));
    expect(strip.volume, closeTo(0.42, 1e-9));
    expect(strip.muted, isTrue);
    expect(strip.soloed, isTrue);
  });

  test('the renamed strip keeps its position in the rack', () {
    engine.addChannel(name: 'a');
    engine.addChannel(name: 'b');
    engine.addChannel(name: 'c');
    recorded.clear();

    // Rename the middle strip — it must stay in the middle.
    engine.renameChannel(engine.channels.value[1], 'beta');

    expect(engine.channels.value.map((c) => c.name), ['a', 'beta', 'c']);
    expect(registry.childrenOfKind(RegistryKinds.mix).map((n) => n.name), [
      'a',
      'beta',
      'c',
    ]);
  });

  test('a display-only rename (same slug) updates in place without a move', () {
    final ch = engine.addChannel(name: 'drum');
    recorded.clear();

    // 'Drum' slugs to 'drum' too — no address change, so no move command.
    engine.renameChannel(ch, 'Drum');

    expect(ch.name, 'Drum'); // same instance, updated in place
    expect(registry.contains(mix('drum')), isTrue);
    expect(stripAt(registry, mix('drum')).name, 'Drum');
    expect(recorded.whereType<MoveEntityCommand>(), isEmpty);
    expect(recorded.whereType<UpdateEntityPayloadCommand>(), hasLength(1));
  });

  test('a name colliding with a sibling slug gets a suffixed address', () {
    engine.addChannel(name: 'bass');
    final other = engine.addChannel(name: 'temp');
    recorded.clear();

    engine.renameChannel(other, 'bass');

    // The slug 'bass' is taken, so the moved entity lands at 'bass_2'.
    expect(registry.contains(mix('bass_2')), isTrue);
    expect(stripAt(registry, mix('bass_2')).name, 'bass');
  });

  test('trims surrounding whitespace before renaming', () {
    final ch = engine.addChannel(name: 'drum');
    recorded.clear();

    engine.renameChannel(ch, '  pad  ');

    expect(registry.contains(mix('pad')), isTrue);
    expect(stripAt(registry, mix('pad')).name, 'pad');
  });

  group('no-ops', () {
    test('renaming to a blank name does nothing', () {
      final ch = engine.addChannel(name: 'drum');
      recorded.clear();

      engine.renameChannel(ch, '   ');

      expect(recorded, isEmpty);
      expect(registry.contains(mix('drum')), isTrue);
      expect(ch.name, 'drum');
    });

    test('renaming to the unchanged name does nothing', () {
      final ch = engine.addChannel(name: 'drum');
      recorded.clear();

      engine.renameChannel(ch, 'drum');

      expect(recorded, isEmpty);
    });

    test('renaming the master channel does nothing', () {
      recorded.clear();

      engine.renameChannel(engine.masterChannel, 'main out');

      expect(recorded, isEmpty);
      expect(engine.masterChannel.name, 'master');
    });
  });
}
