import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/time_domains/time_domain.dart';

import '../test_doubles/fake_project_store.dart';

/// The persistence heart of the v1 migration: a registry carrying `clip.`,
/// `mix.` and `domain.` entities round-trips through the store's per-kind codecs
/// (design `docs/design/project-registry.md` §5), so save → reload restores the
/// whole current app state.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  ProjectSnapshot snapshotOf(ProjectRegistry registry) => ProjectSnapshot(
    manifest: const ProjectManifest(
      name: 'set',
      tempo: 124,
      sceneName: 'intro',
    ),
    registry: registry,
  );

  test(
    'the seeded default project round-trips clip + domain payloads',
    () async {
      final registry = ProjectRegistry();
      seedDefaultProject(registry);

      final store = FakeProjectStore(codecs: defaultEntityCodecs());
      await store.save(snapshotOf(registry));
      final loaded = await store.load();
      addTearDown(loaded.registry.dispose);

      final clip = loaded.registry.entityAt(addr('clip.phrase_a'))!.payload;
      expect(clip, isA<MidiClip>());
      expect((clip! as MidiClip).name, 'phrase A');
      expect((clip as MidiClip).notes, isNotEmpty);

      final domain = loaded.registry.entityAt(addr('domain.drum'))!.payload;
      expect(domain, isA<TimeDomain>());
      expect((domain! as TimeDomain).tempo, 124);

      registry.dispose();
    },
  );

  test('mix strip payloads round-trip as normalised maps', () async {
    final registry = ProjectRegistry();
    registry.createEntity(
      EntityAddress(kind: RegistryKinds.mix, segments: ['drums']),
      payload: const MixStrip(name: 'drums', voice: 3).toJson(),
    );

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    final payload = loaded.registry
        .entityAt(EntityAddress(kind: RegistryKinds.mix, segments: ['drums']))!
        .payload;
    expect(payload, {'name': 'drums', 'voice': 3});
    expect(
      MixStrip.fromJson((payload! as Map).cast()),
      const MixStrip(name: 'drums', voice: 3),
    );

    registry.dispose();
  });

  test('the on-disk entity files are valid, versioned JSON', () async {
    final registry = ProjectRegistry();
    seedDefaultProject(registry);
    registry.createEntity(
      EntityAddress(kind: RegistryKinds.mix, segments: ['pad']),
      payload: const MixStrip(name: 'pad', voice: 1).toJson(),
    );

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));

    // Every entity file parses, carries its kind + schema version, and encodes
    // cleanly (the journal/serializer contract — payloads must be JSON).
    final clipFile =
        jsonDecode(store.files['clip/phrase_a.json']!) as Map<String, Object?>;
    expect(clipFile['kind'], 'clip');
    expect(clipFile['version'], 1);
    expect(clipFile['payload'], isA<Map<String, Object?>>());

    final mixFile =
        jsonDecode(store.files['mix/pad.json']!) as Map<String, Object?>;
    expect(mixFile['kind'], 'mix');
    expect(mixFile['payload'], {'name': 'pad', 'voice': 1});

    registry.dispose();
  });
}
