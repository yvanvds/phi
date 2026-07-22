import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/patch_placement_notice.dart';
import 'package:phi/engine/state/patch_reconciler.dart';
import 'package:yse/yse.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Engine-side `patch.` entity ↔ native instance reconciliation and the source
/// placement lifecycle (issue #220, design `docs/design/patcher.md` §3, §4, §8).
/// Exercised entirely through [FakePatcherGateway]: one native patcher per open
/// patch (its dump parsed on open), torn down on delete, placement mounted /
/// unmounted / started / stopped explicitly, dump refreshed into the payload on
/// save, and a stale placement bus degraded gracefully.
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakePatcherGateway gateway;
  late List<PatchPlacementNotice> notices;

  /// A resolver over a mutable [buses] map: an address present resolves to its
  /// channel id (`null` = master), an absent one degrades (whole record `null`).
  final buses = <EntityAddress, int?>{};
  ({int? channelId})? resolve(EntityAddress address) =>
      buses.containsKey(address) ? (channelId: buses[address]) : null;

  PatchReconciler build() => PatchReconciler(
    gateway: gateway,
    resolveBus: resolve,
    onNotice: notices.add,
  );

  /// A registry holding [patches] keyed by address → payload (stored map-native,
  /// as the codec loads them).
  ProjectRegistry registryWith(Map<EntityAddress, PatchPayload> patches) {
    final registry = ProjectRegistry();
    patches.forEach((address, payload) {
      registry.createEntity(address, payload: payload.toJson());
    });
    return registry;
  }

  setUp(() {
    gateway = FakePatcherGateway();
    notices = [];
    buses.clear();
  });

  group('open / teardown', () {
    test('materialises one native patcher per patch, parsing its dump', () {
      final dump = {'objects': 2, 'cables': 1};
      final registry = registryWith({patch('swirl'): PatchPayload(dump: dump)});
      addTearDown(registry.dispose);

      build().sync(registry);

      expect(gateway.instances, hasLength(1));
      // The loaded dump was parsed into the fresh instance on open.
      expect(gateway.calls, contains('createInstance:1:1'));
      expect(gateway.calls.any((c) => c.startsWith('parseJson:')), isTrue);
    });

    test('keeps one instance across an unrelated re-sync (survives)', () {
      final registry = registryWith({patch('a'): PatchPayload.empty});
      addTearDown(registry.dispose);
      final reconciler = build();

      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('a'));
      // A second sync with the same entity must not re-create or re-parse.
      reconciler.sync(registry);

      expect(reconciler.instanceIdOf(patch('a')), id);
      expect(gateway.calls.where((c) => c.startsWith('createInstance')), [
        'createInstance:1:1',
      ]);
    });

    test('materialises independent instances per patch (keyed by address)', () {
      final registry = registryWith({
        patch('a'): PatchPayload.empty,
        patch('b'): PatchPayload.empty,
      });
      addTearDown(registry.dispose);
      final reconciler = build();

      reconciler.sync(registry);

      expect(reconciler.openPatches, containsAll([patch('a'), patch('b')]));
      expect(
        reconciler.instanceIdOf(patch('a')),
        isNot(reconciler.instanceIdOf(patch('b'))),
      );
    });

    test('tears the native patcher down when its entity is deleted', () {
      final registry = registryWith({patch('gone'): PatchPayload.empty});
      addTearDown(registry.dispose);
      final reconciler = build();

      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('gone'));
      registry.remove(patch('gone'));
      reconciler.sync(registry);

      expect(reconciler.isOpen(patch('gone')), isFalse);
      expect(gateway.calls, contains('disposeInstance:$id'));
      expect(gateway.instances, isEmpty);
    });

    test('teardown disposes every instance without touching the registry', () {
      final registry = registryWith({
        patch('a'): PatchPayload.empty,
        patch('b'): PatchPayload.empty,
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);

      reconciler.teardown();

      expect(reconciler.openPatches, isEmpty);
      expect(gateway.instances, isEmpty);
      // The entities are untouched — a later sync rebuilds from them.
      expect(registry.contains(patch('a')), isTrue);
    });
  });

  group('source placement lifecycle', () {
    test('a loaded, placed patch starts silent — not mounted', () {
      buses[mix('reverb')] = 7;
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('reverb')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();

      reconciler.sync(registry);

      // Placement persisted, but running state does not: no mount on open.
      expect(reconciler.placementOf(patch('src')), mix('reverb'));
      expect(reconciler.isRunning(patch('src')), isFalse);
      expect(gateway.mounted, isFalse);
    });

    test('start mounts the source on its placement bus', () {
      buses[mix('reverb')] = 7;
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('reverb')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('src'));

      final started = reconciler.start(patch('src'));

      expect(started, isTrue);
      expect(reconciler.isRunning(patch('src')), isTrue);
      expect(gateway.calls, contains('mountAsSource:$id:7:1.000'));
    });

    test('stop unmounts the source', () {
      buses[mix('reverb')] = 7;
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('reverb')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('src'));
      reconciler.start(patch('src'));

      reconciler.stop(patch('src'));

      expect(reconciler.isRunning(patch('src')), isFalse);
      expect(gateway.calls, contains('unmountSource:$id'));
      expect(gateway.mounted, isFalse);
    });

    test('a placement on master mounts with a null bus id', () {
      buses[mix('master')] = null; // master → null channel id
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('master')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('src'));

      reconciler.start(patch('src'));

      expect(gateway.calls, contains('mountAsSource:$id:null:1.000'));
    });

    test('an unplaced patch cannot be started', () {
      final registry = registryWith({patch('src'): PatchPayload.empty});
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);

      expect(reconciler.start(patch('src')), isFalse);
      expect(gateway.mounted, isFalse);
      expect(notices, isEmpty); // unplaced is not a degradation.
    });
  });

  group('graceful degradation of a stale placement bus', () {
    test('start on an unknown bus stays unplaced and surfaces a notice', () {
      // The placement names a bus that is not in the live mix (buses empty).
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('ghost')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);

      final started = reconciler.start(patch('src'));

      expect(started, isFalse);
      expect(reconciler.isRunning(patch('src')), isFalse);
      expect(gateway.mounted, isFalse);
      expect(notices, hasLength(1));
      expect(notices.single.patch, patch('src'));
      expect(notices.single.bus, mix('ghost'));
    });

    test('a bus that vanishes while running is unmounted + surfaced', () {
      buses[mix('reverb')] = 7;
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('reverb')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('src'));
      reconciler.start(patch('src'));
      expect(reconciler.isRunning(patch('src')), isTrue);

      // The bus is removed from the live mix, then the registry re-syncs.
      buses.remove(mix('reverb'));
      reconciler.sync(registry);

      expect(reconciler.isRunning(patch('src')), isFalse);
      expect(gateway.calls, contains('unmountSource:$id'));
      expect(notices, hasLength(1));
      expect(notices.single.bus, mix('reverb'));
    });

    test('a running source re-mounts when its bus channel id changes', () {
      buses[mix('reverb')] = 7;
      final registry = registryWith({
        patch('src'): PatchPayload(placement: mix('reverb')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('src'));
      reconciler.start(patch('src'));

      // The bus was rebuilt with a new gateway channel id; a re-sync follows it.
      buses[mix('reverb')] = 9;
      reconciler.sync(registry);

      expect(reconciler.isRunning(patch('src')), isTrue);
      expect(gateway.calls, contains('mountAsSource:$id:9:1.000'));
      expect(notices, isEmpty);
    });
  });

  group('dump-to-payload on save', () {
    test('flush refreshes the entity payload from the live dump', () {
      final registry = registryWith({
        patch('p'): PatchPayload(placement: mix('reverb')),
      });
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('p'))!;

      // Edit the live native graph (two objects added).
      gateway.createObject(id, Obj.dSine);
      gateway.createObject(id, Obj.dDac);

      final recorded = <ProjectCommand>[];
      reconciler.flushToPayloads(registry, recorded.add);

      final payload = PatchPayload.fromJson(
        (registry.entityAt(patch('p'))!.payload! as Map).cast(),
      );
      // The fake dumps a structured, re-parseable graph: two objects, no cables.
      expect(payload.dump['objects'], hasLength(2));
      expect(payload.dump['cables'], isEmpty);
      // Placement is carried through untouched by the dump refresh.
      expect(payload.placement, mix('reverb'));
      // The refresh is recorded so it dirty-tracks + journals like any edit.
      expect(recorded, hasLength(1));
    });

    test('flush writes nothing for a patch whose dump is unchanged', () {
      final registry = registryWith({patch('p'): PatchPayload.empty});
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('p'))!;
      gateway.createObject(id, Obj.dSine);

      final recorded = <ProjectCommand>[];
      reconciler.flushToPayloads(registry, recorded.add); // first: 1 object
      reconciler.flushToPayloads(registry, recorded.add); // second: no change

      expect(recorded, hasLength(1));
    });

    test('an edit round-trips: flush → reload parses the refreshed dump', () {
      final registry = registryWith({patch('p'): PatchPayload.empty});
      addTearDown(registry.dispose);
      final reconciler = build();
      reconciler.sync(registry);
      final id = reconciler.instanceIdOf(patch('p'))!;
      gateway.createObject(id, Obj.dSine);
      reconciler.flushToPayloads(registry, (_) {});

      // Simulate a reload: a fresh gateway + reconciler over the saved registry.
      final reloadedGateway = FakePatcherGateway();
      final reloaded = PatchReconciler(
        gateway: reloadedGateway,
        resolveBus: resolve,
        onNotice: notices.add,
      );
      reloaded.sync(registry);

      // On open, the reconciler hands the entity payload's (refreshed) dump to
      // parseJson — so a reload runs the edited patch, not the seed. The fake logs
      // only the content length, so assert against the exact re-encoded dump.
      final reloadedDump = PatchPayload.fromJson(
        (registry.entityAt(patch('p'))!.payload! as Map).cast(),
      ).dump;
      expect(reloaded.isOpen(patch('p')), isTrue);
      expect(
        reloadedGateway.calls,
        contains('parseJson:${jsonEncode(reloadedDump).length}'),
      );
    });
  });
}
