import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
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

  test('the seeded default project round-trips clip + domain payloads', () async {
    final registry = ProjectRegistry();
    seedDefaultProject(registry);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    final clip = loaded.registry.entityAt(addr('clip.phrase_a'))!.payload;
    // The clip payload is a v2 ClipDocument map (source notes + interpretation).
    final document = ClipDocument.fromJson((clip! as Map).cast());
    expect(document.source.notes, isNotEmpty);
    // The loop flag survives the store round trip (issue #184).
    expect(document.loop, isTrue);
    // The transform chain round-tripped alongside the source (issue #135).
    expect(document.chain, isNotEmpty);

    final domain = loaded.registry.entityAt(addr('domain.drum'))!.payload;
    expect(domain, isA<TimeDomain>());
    expect((domain! as TimeDomain).tempo, 124);

    registry.dispose();
  });

  test('mix strip payloads round-trip live state as normalised maps', () async {
    final registry = ProjectRegistry();
    const strip = MixStrip(voice: 3, volume: 0.42, muted: true, soloed: true);
    registry.createEntity(
      EntityAddress(kind: RegistryKinds.mix, segments: ['drums']),
      payload: strip.toJson(),
    );

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    final payload = loaded.registry
        .entityAt(EntityAddress(kind: RegistryKinds.mix, segments: ['drums']))!
        .payload;
    expect(payload, {
      'voice': 3,
      'volume': 0.42,
      'muted': true,
      'soloed': true,
      'return': false,
      'sends': <Object?>[],
      'inserts': <Object?>[],
    });
    // The live volume/mute/solo survive the save/reload (issue #136).
    expect(MixStrip.fromJson((payload! as Map).cast()), strip);

    registry.dispose();
  });

  test('the on-disk entity files are valid, versioned JSON', () async {
    final registry = ProjectRegistry();
    seedDefaultProject(registry);
    registry.createEntity(
      EntityAddress(kind: RegistryKinds.mix, segments: ['pad']),
      payload: const MixStrip(voice: 1).toJson(),
    );

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));

    // Every entity file parses, carries its kind + schema version, and encodes
    // cleanly (the journal/serializer contract — payloads must be JSON).
    final clipFile =
        jsonDecode(store.files['clip/phrase_a.json']!) as Map<String, Object?>;
    expect(clipFile['kind'], 'clip');
    expect(clipFile['version'], 2);
    expect(clipFile['payload'], isA<Map<String, Object?>>());

    final mixFile =
        jsonDecode(store.files['mix/pad.json']!) as Map<String, Object?>;
    expect(mixFile['kind'], 'mix');
    expect(mixFile['version'], 4);
    expect(mixFile['payload'], {
      'voice': 1,
      'volume': 1.0,
      'muted': false,
      'soloed': false,
      'return': false,
      'sends': <Object?>[],
      'inserts': <Object?>[],
    });

    registry.dispose();
  });
}
