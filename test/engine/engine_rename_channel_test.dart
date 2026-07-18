import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/commands/move_entity_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// Renaming a user channel (issue #141, re-aligned by #166): a strip has no
/// separate display name — it is named by its address leaf — so a rename is
/// purely a **move** of the `mix.` entity to the slug of the new name (design §4,
/// rename = refactor). The move rematerialises the channel — its live
/// volume/mute/solo/sends ride the payload and survive — and is journaled for
/// dirty-tracking and recovery. A name whose slug is unchanged is a no-op: the
/// name already *is* the slug, so there is nothing to rename.
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

  test('renames by moving the address to the slug of the new name', () {
    engine.addChannel(name: 'drums');
    recorded.clear();

    engine.renameChannel(engine.channels.value.single, 'lead synth');

    // The entity moved to the slug of the new name …
    expect(registry.contains(mix('drums')), isFalse);
    expect(registry.contains(mix('lead_synth')), isTrue);
    // … and the channel is named by that address leaf (the one name).
    expect(engine.channels.value.single.name, 'lead_synth');
    // A live gateway channel exists under the new name.
    expect(gateway.channels.values.map((c) => c.name), contains('lead_synth'));
  });

  test('records a single move (journal-encodable)', () {
    engine.addChannel(name: 'drums');
    recorded.clear();

    engine.renameChannel(engine.channels.value.single, 'bass');

    expect(recorded, hasLength(1));
    expect(recorded.single, isA<MoveEntityCommand>());
    final moveJson = recorded.single.toJson();
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
    // Persisted alongside the move, so a reload restores them too.
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

  test('a name colliding with a sibling slug gets a suffixed address', () {
    engine.addChannel(name: 'bass');
    final other = engine.addChannel(name: 'temp');
    recorded.clear();

    engine.renameChannel(other, 'bass');

    // The slug 'bass' is taken, so the moved entity lands at 'bass_2'.
    expect(registry.contains(mix('bass_2')), isTrue);
    expect(engine.channels.value.map((c) => c.name), ['bass', 'bass_2']);
  });

  test('trims surrounding whitespace before renaming', () {
    final ch = engine.addChannel(name: 'drum');
    recorded.clear();

    engine.renameChannel(ch, '  pad  ');

    expect(registry.contains(mix('pad')), isTrue);
    expect(engine.channels.value.single.name, 'pad');
  });

  group('no-ops', () {
    test('a same-slug rename does nothing (the name is already the slug)', () {
      final ch = engine.addChannel(name: 'drum');
      recorded.clear();

      // 'Drum' slugs to 'drum' — the current address — so there is nothing to
      // rename: no move, no payload command, the name is unchanged.
      engine.renameChannel(ch, 'Drum');

      expect(recorded, isEmpty);
      expect(ch.name, 'drum');
      expect(registry.contains(mix('drum')), isTrue);
    });

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
