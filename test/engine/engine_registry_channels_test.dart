import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/commands/create_entity_command.dart';
import 'package:phi/domain/project/commands/remove_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// The "engine consumes the registry" half of the v1 migration (design §8): the
/// registry is the source of truth for the channel set and the engine
/// materialises its `MixerChannel`s from `mix.` entities.
void main() {
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakeYseGateway gateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  test('addChannel writes a mix. entity into the bound registry', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    engine.start();
    engine.bindProject(registry);

    final ch = engine.addChannel(name: 'drums');

    expect(registry.contains(mix('drums')), isTrue);
    final payload = registry.entityAt(mix('drums'))!.payload;
    expect(
      MixStrip.fromJson((payload! as Map).cast()),
      const MixStrip(voice: 1),
    );
    // The materialised channel is the one exposed to the surface.
    expect(engine.channels.value, [ch]);
    expect(ch.name, 'drums');
  });

  test('addChannel/removeChannel record their commands for journaling', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    final recorded = <ProjectCommand>[];
    engine.start();
    engine.bindProject(registry, recordCommand: recorded.add);

    final ch = engine.addChannel(name: 'pad');
    engine.removeChannel(ch);

    expect(recorded, hasLength(2));
    expect(recorded[0], isA<CreateEntityCommand>());
    expect(recorded[1], isA<RemoveEntityCommand>());
    // The commands are JSON-encodable (the journal contract).
    expect(recorded[0].toJson()['type'], 'create_entity');
    expect(recorded[1].toJson()['type'], 'remove_entity');
    expect(registry.contains(mix('pad')), isFalse);
    expect(engine.channels.value, isEmpty);
  });

  test('duplicate display names get distinct addresses', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    engine.start();
    engine.bindProject(registry);

    engine.addChannel(name: 'drum');
    engine.addChannel(name: 'drum');

    expect(registry.contains(mix('drum')), isTrue);
    expect(registry.contains(mix('drum_2')), isTrue);
    expect(engine.channels.value, hasLength(2));
  });

  test('binding a registry materialises its existing mix. entities', () {
    final registry = ProjectRegistry();
    addTearDown(registry.dispose);
    registry.createEntity(
      mix('bass'),
      payload: const MixStrip(voice: 4).toJson(),
    );
    registry.createEntity(
      mix('lead'),
      payload: const MixStrip(voice: 2).toJson(),
    );

    engine.start();
    engine.bindProject(registry);

    expect(engine.channels.value, hasLength(2));
    expect(engine.channels.value.map((c) => c.name), ['bass', 'lead']);
    expect(engine.channels.value.map((c) => c.voice), [4, 2]);
    // Each materialised channel has a live gateway channel.
    expect(
      gateway.channels.values.map((c) => c.name),
      containsAll(['bass', 'lead']),
    );
  });

  test('rebinding a fresh registry tears down the previous channels', () {
    final projectA = ProjectRegistry()
      ..createEntity(mix('a'), payload: const MixStrip(voice: 1).toJson());
    final projectB = ProjectRegistry()
      ..createEntity(mix('b'), payload: const MixStrip(voice: 1).toJson());
    addTearDown(projectA.dispose);
    addTearDown(projectB.dispose);

    engine.start();
    engine.bindProject(projectA);
    expect(engine.channels.value.single.name, 'a');

    engine.bindProject(projectB);
    expect(engine.channels.value.single.name, 'b');
    // The old gateway channel was destroyed; only b's remains.
    expect(gateway.channels.values.map((c) => c.name), ['b']);
  });

  test('a bare engine still adds channels into its private registry', () {
    // No bindProject: the engine owns an empty registry nobody persists.
    engine.start();
    final ch = engine.addChannel(name: 'drums');
    expect(engine.channels.value, [ch]);
    expect(engine.mixRegistry.contains(mix('drums')), isTrue);
  });
}
