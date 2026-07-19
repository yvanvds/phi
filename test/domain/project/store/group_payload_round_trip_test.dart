@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/store/group_metadata.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/real_project_store.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';

import '../test_doubles/fake_project_store.dart';

/// Persistence coverage for kind-declared group payloads (issue #165): a `mix.`
/// group is a bus, so its `_group.json` carries a payload alongside the cosmetic
/// order/colour metadata, while an undeclared kind (`clip.`) stays byte-for-byte
/// as it was.
EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

const _manifest = ProjectManifest(
  name: 'my_set',
  tempo: 124,
  sceneName: 'intro',
);

ProjectSnapshot snapshotOf(
  ProjectRegistry registry, {
  Map<EntityAddress, GroupMetadata> groups = const {},
}) => ProjectSnapshot(
  manifest: _manifest,
  registry: registry,
  groupMetadata: groups,
);

FakeProjectStore mixStore() => FakeProjectStore(
  codecs: defaultEntityCodecs(),
  groupPayloadKinds: defaultGroupPayloadKinds(),
);

void main() {
  group('mix group bus round-trip', () {
    test('a mix group round-trips volume/mute/solo and sends', () async {
      final registry = ProjectRegistry();
      // The return the group bus sends to, plus a child strip under the bus.
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const MixStrip(
          voice: 3,
          volume: 0.42,
          muted: true,
          soloed: true,
        ).toJson(),
        references: {addr('mix.verb')}, // the bus's send target
      );
      registry.createEntity(addr('mix.drums.kick'));

      final store = mixStore();
      await store.save(snapshotOf(registry));
      final loaded = await store.load();
      addTearDown(loaded.registry.dispose);

      // The bus payload — volume/mute/solo — survives.
      final payload = loaded.registry.groupAt(addr('mix.drums'))!.payload;
      expect(
        MixStrip.fromJson((payload! as Map).cast()),
        const MixStrip(voice: 3, volume: 0.42, muted: true, soloed: true),
      );
      // The send (a reference to the return) survives, back-index and all.
      expect(loaded.registry.referencesOf(addr('mix.drums')), {
        addr('mix.verb'),
      });
      expect(loaded.registry.referrersOf(addr('mix.verb')), {
        addr('mix.drums'),
      });
      // The child strip under the bus survives.
      expect(loaded.registry.contains(addr('mix.drums.kick')), isTrue);

      registry.dispose();
    });

    test('the _group.json carries a versioned payload envelope', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const MixStrip(voice: 2).toJson(),
        references: {addr('mix.verb')},
      );

      final store = mixStore();
      await store.save(
        snapshotOf(
          registry,
          groups: {addr('mix.drums'): const GroupMetadata(color: 'amber')},
        ),
      );

      final json =
          jsonDecode(store.files['mix/drums/_group.json']!)
              as Map<String, Object?>;
      expect(json['kind'], 'mix');
      expect(json['version'], 4);
      // The envelope's `name` is the group's own address leaf, not a payload
      // field (the payload no longer carries a display name).
      expect(json['name'], 'drums');
      expect(json['references'], ['mix.verb']);
      expect(json['payload'], {
        'voice': 2,
        'volume': 1.0,
        'muted': false,
        'soloed': false,
        'return': false,
        'sends': <Object?>[],
        'inserts': <Object?>[],
      });
      // Cosmetic metadata coexists in the same file.
      expect(json['color'], 'amber');

      registry.dispose();
    });

    test('a payload-free mix group writes no _group.json', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('mix.drums.kick'));

      final store = mixStore();
      await store.save(snapshotOf(registry));

      expect(store.files.containsKey('mix/drums/_group.json'), isFalse);

      registry.dispose();
    });

    test('a group-payload edit re-persists on a dirty save', () async {
      final registry = ProjectRegistry();
      registry.createGroup(
        addr('mix.drums'),
        payload: const MixStrip(voice: 2).toJson(),
      );
      final store = mixStore();
      await store.save(snapshotOf(registry));

      registry.updateGroupPayload(
        addr('mix.drums'),
        const MixStrip(voice: 2, volume: 0.1, muted: true).toJson(),
      );
      await store.save(snapshotOf(registry), dirty: {addr('mix.drums')});

      final loaded = await store.load();
      addTearDown(loaded.registry.dispose);
      final payload = loaded.registry.groupAt(addr('mix.drums'))!.payload;
      final strip = MixStrip.fromJson((payload! as Map).cast());
      expect(strip.volume, 0.1);
      expect(strip.muted, isTrue);

      registry.dispose();
    });
  });

  group('undeclared kinds are unaffected', () {
    test('a clip group _group.json carries order/colour only', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.drums.kick'));
      registry.createEntity(addr('clip.drums.snare'));

      final store = mixStore();
      await store.save(
        snapshotOf(
          registry,
          groups: {
            addr('clip.drums'): const GroupMetadata(
              order: ['snare', 'kick'],
              color: 'red',
            ),
          },
        ),
      );

      // Byte-for-byte the pre-#165 shape: no kind/version/name/payload keys.
      final json =
          jsonDecode(store.files['clip/drums/_group.json']!)
              as Map<String, Object?>;
      expect(json, {
        'order': ['snare', 'kick'],
        'color': 'red',
      });

      registry.dispose();
    });

    test('a payload on an undeclared-kind group is never written', () async {
      final registry = ProjectRegistry();
      // clip is NOT in groupPayloadKinds, so a stray payload is not persisted.
      registry.createGroup(
        addr('clip.drums'),
        payload: const {'name': 'drums'},
      );
      registry.createEntity(addr('clip.drums.kick'));

      final store = mixStore();
      await store.save(snapshotOf(registry));

      expect(store.files.containsKey('clip/drums/_group.json'), isFalse);
      final loaded = await store.load();
      addTearDown(loaded.registry.dispose);
      expect(loaded.registry.groupAt(addr('clip.drums'))!.payload, isNull);

      registry.dispose();
    });
  });

  group('real filesystem', () {
    late Directory tempDir;
    late Directory projectDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('phi_group_payload_');
      projectDir = Directory(p.join(tempDir.path, 'my_set.phi'));
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a mix group bus round-trips through a real .phi folder', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('mix.verb'));
      registry.createGroup(
        addr('mix.drums'),
        payload: const MixStrip(voice: 4, volume: 0.7).toJson(),
        references: {addr('mix.verb')},
      );

      final store = RealProjectStore(
        projectDir,
        codecs: defaultEntityCodecs(),
        groupPayloadKinds: defaultGroupPayloadKinds(),
      );
      await store.save(snapshotOf(registry));

      final loaded = await store.load();
      addTearDown(loaded.registry.dispose);
      final payload = loaded.registry.groupAt(addr('mix.drums'))!.payload;
      expect(MixStrip.fromJson((payload! as Map).cast()).volume, 0.7);
      expect(loaded.registry.referrersOf(addr('mix.verb')), {
        addr('mix.drums'),
      });

      registry.dispose();
    });
  });
}
