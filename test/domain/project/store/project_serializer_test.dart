import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/store/entity_payload_codec.dart';
import 'package:phi/domain/project/store/group_metadata.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_serializer.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';

import '../test_doubles/fake_project_store.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

const _manifest = ProjectManifest(
  name: 'my_set',
  tempo: 124,
  sceneName: 'intro',
);

/// A codec that wraps an int payload as `{"v": n}` at schema version 2 — the
/// stand-in for a real per-kind codec, and the probe for the migration seam.
class _WrappingCodec implements EntityPayloadCodec {
  const _WrappingCodec();

  @override
  int get version => 2;

  @override
  Object? encode(Object? payload) => {'v': payload};

  @override
  Object? decode(Object? json, int version) {
    lastDecodeVersion = version;
    return (json! as Map<String, Object?>)['v'];
  }

  static int? lastDecodeVersion;
}

void main() {
  ProjectSnapshot snapshotOf(
    ProjectRegistry registry, {
    Map<EntityAddress, GroupMetadata> groups = const {},
  }) => ProjectSnapshot(
    manifest: _manifest,
    registry: registry,
    groupMetadata: groups,
  );

  group('full save / load round-trip', () {
    test('preserves the manifest, the tree, and references', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.lead_line'), payload: {'notes': 3});
      registry.createEntity(addr('clip.drums.intro_fill'));
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.perc')},
      );
      registry.createEntity(addr('mix.perc'));

      final store = FakeProjectStore();
      await store.save(snapshotOf(registry));
      final loaded = await store.load();

      expect(loaded.manifest, _manifest);
      expect(loaded.registry.contains(addr('clip.lead_line')), isTrue);
      expect(loaded.registry.entityAt(addr('clip.lead_line'))!.payload, const {
        'notes': 3,
      });
      expect(loaded.registry.contains(addr('clip.drums.intro_fill')), isTrue);
      expect(loaded.registry.groupAt(addr('clip.drums')), isNotNull);
      expect(loaded.registry.referencesOf(addr('voice.bells')), {
        addr('mix.perc'),
      });
      // The back-reference index rebuilds from the reloaded edges.
      expect(loaded.registry.referrersOf(addr('mix.perc')), {
        addr('voice.bells'),
      });
    });

    test(
      'entity file carries kind, version, name and mirrors the address',
      () async {
        final registry = ProjectRegistry();
        registry.createEntity(addr('clip.drums.intro_fill'), payload: {'n': 1});

        final store = FakeProjectStore();
        await store.save(snapshotOf(registry));

        const path = 'clip/drums/intro_fill.json';
        expect(store.files.containsKey(path), isTrue);
        final json = jsonDecode(store.files[path]!) as Map<String, Object?>;
        expect(json['kind'], 'clip');
        expect(json['version'], 1);
        expect(json['name'], 'intro_fill');
        expect(json['payload'], const {'n': 1});
        // Pretty-printed with a trailing newline for clean diffs.
        expect(store.files[path]!.endsWith('\n'), isTrue);
        expect(store.files[path]!.contains('\n  '), isTrue);
      },
    );

    test('manifest lands at project.json', () async {
      final store = FakeProjectStore();
      await store.save(snapshotOf(ProjectRegistry()));
      expect(store.files.containsKey('project.json'), isTrue);
    });

    test('a dangling reference survives the round-trip', () async {
      final registry = ProjectRegistry();
      registry.createEntity(
        addr('voice.bells'),
        references: {addr('mix.gone')},
      );
      final store = FakeProjectStore();
      await store.save(snapshotOf(registry));
      final loaded = await store.load();
      expect(loaded.registry.referencesOf(addr('voice.bells')), {
        addr('mix.gone'),
      });
    });
  });

  group('per-kind payload codec (migration seam)', () {
    test('encodes with the codec version and decodes back', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('synth.fm_bells'), payload: 7);

      final store = FakeProjectStore(codecs: const {'synth': _WrappingCodec()});
      await store.save(snapshotOf(registry));

      final json =
          jsonDecode(store.files['synth/fm_bells.json']!)
              as Map<String, Object?>;
      expect(json['version'], 2);
      expect(json['payload'], const {'v': 7});

      _WrappingCodec.lastDecodeVersion = null;
      final loaded = await store.load();
      expect(loaded.registry.entityAt(addr('synth.fm_bells'))!.payload, 7);
      expect(_WrappingCodec.lastDecodeVersion, 2);
    });
  });

  group('group metadata (_group.json)', () {
    test('restores authored child order on load', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.drums.a_kick'));
      registry.createEntity(addr('clip.drums.z_snare'));
      registry.createEntity(addr('clip.drums.m_hat'));

      final store = FakeProjectStore();
      await store.save(
        snapshotOf(
          registry,
          groups: {
            addr('clip.drums'): const GroupMetadata(
              order: ['z_snare', 'a_kick', 'm_hat'],
              color: 'amber',
            ),
          },
        ),
      );
      expect(store.files.containsKey('clip/drums/_group.json'), isTrue);

      final loaded = await store.load();
      final names = loaded.registry
          .childrenOfGroup(addr('clip.drums'))
          .map((n) => n.name)
          .toList();
      expect(names, ['z_snare', 'a_kick', 'm_hat']);
      expect(loaded.registry.groupAt(addr('clip.drums')), isNotNull);
      expect(
        loaded.groupMetadata[addr('clip.drums')],
        const GroupMetadata(
          order: ['z_snare', 'a_kick', 'm_hat'],
          color: 'amber',
        ),
      );
    });

    test('children with no _group.json load alphabetically', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.drums.z_snare'));
      registry.createEntity(addr('clip.drums.a_kick'));

      final store = FakeProjectStore();
      await store.save(snapshotOf(registry));
      final loaded = await store.load();
      final names = loaded.registry
          .childrenOfGroup(addr('clip.drums'))
          .map((n) => n.name)
          .toList();
      expect(names, ['a_kick', 'z_snare']);
      expect(loaded.groupMetadata, isEmpty);
    });

    test('an empty GroupMetadata writes no file', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.drums.a_kick'));
      final store = FakeProjectStore();
      await store.save(
        snapshotOf(
          registry,
          groups: {addr('clip.drums'): const GroupMetadata()},
        ),
      );
      expect(store.files.containsKey('clip/drums/_group.json'), isFalse);
    });
  });

  group('dirty save', () {
    test(
      'rewrites only dirty entities and leaves the rest byte-identical',
      () async {
        final registry = ProjectRegistry();
        registry.createEntity(addr('clip.a'), payload: {'v': 1});
        registry.createEntity(addr('clip.b'), payload: {'v': 1});

        final store = FakeProjectStore();
        await store.save(snapshotOf(registry));
        final untouched = store.files['clip/b.json'];

        // Mutate a — represented as a fresh payload — and dirty-save only a.
        registry.remove(addr('clip.a'));
        registry.createEntity(addr('clip.a'), payload: {'v': 2});
        await store.save(snapshotOf(registry), dirty: {addr('clip.a')});

        final aJson =
            jsonDecode(store.files['clip/a.json']!) as Map<String, Object?>;
        expect(aJson['payload'], const {'v': 2});
        expect(store.files['clip/b.json'], untouched);
        expect(store.saveCount, 2);
      },
    );

    test('deletes the file of a removed entity', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.a'));
      registry.createEntity(addr('clip.b'));
      final store = FakeProjectStore();
      await store.save(snapshotOf(registry));
      expect(store.files.containsKey('clip/a.json'), isTrue);

      registry.remove(addr('clip.a'));
      await store.save(snapshotOf(registry), dirty: {addr('clip.a')});

      expect(store.files.containsKey('clip/a.json'), isFalse);
      expect(store.files.containsKey('clip/b.json'), isTrue);
    });

    test(
      'a group move rewrites the relocated subtree and deletes the old one',
      () async {
        final registry = ProjectRegistry();
        registry.createEntity(addr('clip.drums.kick'));
        registry.createEntity(addr('clip.drums.snare'));
        final store = FakeProjectStore();
        await store.save(snapshotOf(registry));

        // Rename clip.drums -> clip.perc: the command reports {from, to, ...}.
        registry.move(addr('clip.drums'), addr('clip.perc'));
        await store.save(
          snapshotOf(registry),
          dirty: {addr('clip.drums'), addr('clip.perc')},
        );

        expect(
          store.files.keys.where((k) => k.startsWith('clip/drums/')),
          isEmpty,
        );
        expect(store.files.containsKey('clip/perc/kick.json'), isTrue);
        expect(store.files.containsKey('clip/perc/snare.json'), isTrue);

        final loaded = await store.load();
        expect(loaded.registry.contains(addr('clip.perc.kick')), isTrue);
        expect(loaded.registry.contains(addr('clip.drums.kick')), isFalse);
      },
    );

    test('deletes a removed group\'s whole subtree', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.drums.kick'));
      registry.createEntity(addr('clip.drums.snare'));
      registry.createEntity(addr('clip.lead'));
      final store = FakeProjectStore();
      await store.save(
        snapshotOf(
          registry,
          groups: {addr('clip.drums'): const GroupMetadata(color: 'red')},
        ),
      );

      registry.remove(addr('clip.drums'));
      await store.save(snapshotOf(registry), dirty: {addr('clip.drums')});

      expect(
        store.files.keys.where((k) => k.startsWith('clip/drums/')),
        isEmpty,
      );
      expect(store.files.containsKey('clip/lead.json'), isTrue);
    });
  });

  group('full save mirrors the registry', () {
    test('prunes files the registry no longer holds', () async {
      final registry = ProjectRegistry();
      registry.createEntity(addr('clip.a'));
      registry.createEntity(addr('clip.b'));
      final store = FakeProjectStore();
      await store.save(snapshotOf(registry));

      registry.remove(addr('clip.b'));
      await store.save(snapshotOf(registry)); // full save, no dirty set

      expect(store.files.containsKey('clip/a.json'), isTrue);
      expect(store.files.containsKey('clip/b.json'), isFalse);
    });
  });

  group('store lifecycle', () {
    test('exists reflects the manifest presence', () async {
      final store = FakeProjectStore();
      expect(await store.exists(), isFalse);
      await store.save(snapshotOf(ProjectRegistry()));
      expect(await store.exists(), isTrue);
    });

    test('load throws when the folder is not a project', () async {
      const serializer = ProjectSerializer();
      expect(() => serializer.readSnapshot(const {}), throwsFormatException);
    });
  });
}
