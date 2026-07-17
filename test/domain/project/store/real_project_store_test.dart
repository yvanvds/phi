@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/store/group_metadata.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/real_project_store.dart';

EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

/// End-to-end coverage of the persistence layer against a *real* `.phi` folder
/// on disk — the strongest exercise available for a data-layer seam with no UI
/// surface. It drives `RealProjectStore`'s `dart:io` path (real directories,
/// real files, real JSON), which the in-memory fake never touches.
void main() {
  late Directory tempDir;
  late Directory projectDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('phi_store_test_');
    projectDir = Directory(p.join(tempDir.path, 'my_set.phi'));
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ProjectSnapshot snapshotOf(
    ProjectRegistry registry, {
    Map<EntityAddress, GroupMetadata> groups = const {},
    ProjectManifest manifest = const ProjectManifest(
      name: 'my_set',
      tempo: 124,
      sceneName: 'intro',
    ),
  }) => ProjectSnapshot(
    manifest: manifest,
    registry: registry,
    groupMetadata: groups,
  );

  test('save then load round-trips a project through the filesystem', () async {
    final registry = ProjectRegistry();
    registry.createEntity(addr('clip.drums.intro_fill'), payload: {'beats': 4});
    registry.createEntity(addr('voice.bells'), references: {addr('mix.perc')});
    registry.createEntity(addr('mix.perc'));

    final store = RealProjectStore(projectDir);
    expect(await store.exists(), isFalse);

    await store.save(
      snapshotOf(
        registry,
        groups: {
          addr('clip.drums'): const GroupMetadata(
            order: ['intro_fill'],
            color: 'amber',
          ),
        },
      ),
    );

    // The layout is real files on disk mirroring each address.
    expect(await store.exists(), isTrue);
    expect(
      await File(p.join(projectDir.path, 'project.json')).exists(),
      isTrue,
    );
    expect(
      await File(
        p.join(projectDir.path, 'clip', 'drums', 'intro_fill.json'),
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        p.join(projectDir.path, 'clip', 'drums', '_group.json'),
      ).exists(),
      isTrue,
    );
    expect(await Directory(p.join(projectDir.path, 'assets')).exists(), isTrue);

    // A fresh store over the same folder reconstructs the whole snapshot.
    final loaded = await RealProjectStore(projectDir).load();
    expect(
      loaded.manifest,
      const ProjectManifest(name: 'my_set', tempo: 124, sceneName: 'intro'),
    );
    expect(
      loaded.registry.entityAt(addr('clip.drums.intro_fill'))!.payload,
      const {'beats': 4},
    );
    expect(loaded.registry.referencesOf(addr('voice.bells')), {
      addr('mix.perc'),
    });
    expect(loaded.registry.referrersOf(addr('mix.perc')), {
      addr('voice.bells'),
    });
    expect(
      loaded.groupMetadata[addr('clip.drums')],
      const GroupMetadata(order: ['intro_fill'], color: 'amber'),
    );
  });

  test('entity JSON on disk is pretty-printed and address-mirrored', () async {
    final registry = ProjectRegistry();
    registry.createEntity(addr('clip.lead_line'), payload: {'n': 1});
    await RealProjectStore(projectDir).save(snapshotOf(registry));

    final file = File(p.join(projectDir.path, 'clip', 'lead_line.json'));
    final raw = await file.readAsString();
    expect(raw.endsWith('\n'), isTrue);
    expect(raw.contains('\n  '), isTrue); // indented
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['kind'], 'clip');
    expect(json['name'], 'lead_line');
    expect(json['version'], 1);
  });

  test('dirty save deletes a removed entity file on disk', () async {
    final registry = ProjectRegistry();
    registry.createEntity(addr('clip.a'));
    registry.createEntity(addr('clip.b'));
    final store = RealProjectStore(projectDir);
    await store.save(snapshotOf(registry));
    expect(
      await File(p.join(projectDir.path, 'clip', 'a.json')).exists(),
      isTrue,
    );

    registry.remove(addr('clip.a'));
    await store.save(snapshotOf(registry), dirty: {addr('clip.a')});

    expect(
      await File(p.join(projectDir.path, 'clip', 'a.json')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(projectDir.path, 'clip', 'b.json')).exists(),
      isTrue,
    );
  });

  test('load on a missing folder throws a clear FormatException', () async {
    expect(RealProjectStore(projectDir).load(), throwsFormatException);
  });
}
