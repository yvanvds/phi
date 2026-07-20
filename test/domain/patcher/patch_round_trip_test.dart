import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/store/project_manifest.dart';
import 'package:phi/domain/project/store/project_snapshot.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';

import '../project/test_doubles/fake_project_store.dart';

/// The patcher-domain acceptance test (issue #218, design
/// `docs/design/patcher.md` §3): a `patch.` entity whose payload is the engine
/// dump round-trips identity through the store's per-kind codec, and the
/// back-reference index surfaces a placement that references the patch when a
/// delete would strand it.
void main() {
  final patchAddr = EntityAddress.parse('patch.swirl');
  final placementAddr = EntityAddress.parse('fx.swirl_insert');

  // A stand-in engine dump — graph and layout both ride here (opaque to Phi).
  final dump = <String, Object?>{
    'objects': [
      {'id': 1, 'type': '~sine', 'x': 40.0, 'y': 20.0},
      {'id': 2, 'type': '~dac', 'x': 220.0, 'y': 20.0},
    ],
    'cables': [
      {'from': 1, 'outlet': 0, 'to': 2, 'inlet': 0},
    ],
  };
  final patch = PatchPayload(dump: dump);

  // A future `fx.` placement of kind `patcherInsert` wrapping the patch
  // reference (design §4 role 2). The fx→patch edge is declared explicitly here
  // because that role's UI waits on epic #203; the seam it needs — delete-impact
  // listing the referent — is what this test pins down.
  const placement = FxDefinition(kind: FxKind.patcherInsert);

  ProjectRegistry buildRegistry() {
    final registry = ProjectRegistry();
    registry.createEntity(patchAddr, payload: patch);
    registry.createEntity(
      placementAddr,
      payload: placement.toJson(),
      references: {patchAddr},
    );
    return registry;
  }

  ProjectSnapshot snapshotOf(ProjectRegistry registry) => ProjectSnapshot(
    manifest: const ProjectManifest(
      name: 'patch_set',
      tempo: 120,
      sceneName: 'intro',
    ),
    registry: registry,
  );

  test('the patch kind is registered with a real codec', () {
    expect(defaultEntityCodecs()[RegistryKinds.patch], isNotNull);
  });

  test('delete-impact surfaces a placement referent', () {
    final registry = buildRegistry();
    addTearDown(registry.dispose);

    // Deleting the patch would strand the placement that references it.
    expect(registry.impactOfRemoving(patchAddr).referrers, [placementAddr]);
    // The placement itself is safe — nothing points at it.
    expect(registry.impactOfRemoving(placementAddr).isSafe, isTrue);
  });

  test('the patch payload round-trips identity through save/load', () async {
    final registry = buildRegistry();
    addTearDown(registry.dispose);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    final payload = (loaded.registry.entityAt(patchAddr)!.payload! as Map)
        .cast<String, Object?>();
    expect(PatchPayload.fromJson(payload), patch);
    expect(store.files.containsKey('patch/swirl.json'), isTrue);
  });

  test('the placement reference survives a store reload', () async {
    final registry = buildRegistry();
    addTearDown(registry.dispose);

    final store = FakeProjectStore(codecs: defaultEntityCodecs());
    await store.save(snapshotOf(registry));
    final loaded = await store.load();
    addTearDown(loaded.registry.dispose);

    // Delete-impact works identically on the reloaded registry — the fx→patch
    // edge was persisted and re-indexed.
    expect(loaded.registry.impactOfRemoving(patchAddr).referrers, [
      placementAddr,
    ]);
  });
}
