import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:yse/yse.dart';

import 'test_doubles/fake_patcher_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// `PhiEngine` wiring of the per-entity patch reconciler (issue #220): a bound
/// project's `patch.` entities materialise native patchers, their source
/// placement resolves against the live mix, start/stop toggle the source, a save
/// flush dumps live patchers back into their payloads, a stale placement bus
/// degrades into [PhiEngine.lastPatchNotice], and a project swap tears them down.
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakeYseGateway yse;
  late FakePatcherGateway patcher;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    patcher = FakePatcherGateway();
    engine = PhiEngine(
      yse,
      patcherGateway: patcher,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    engine.start();
  });

  tearDown(() async {
    await engine.dispose();
    await yse.dispose();
  });

  ProjectRegistry registryWith(Map<EntityAddress, Object> entities) {
    final registry = ProjectRegistry();
    entities.forEach((address, payload) {
      registry.createEntity(
        address,
        payload: payload is PatchPayload
            ? payload.toJson()
            : payload is MixStrip
            ? payload.toJson()
            : payload,
      );
    });
    return registry;
  }

  test('a bound patch entity materialises a native patcher', () {
    final registry = registryWith({patch('swirl'): PatchPayload.empty});
    addTearDown(registry.dispose);

    engine.bindProject(registry);

    expect(engine.patches.isOpen(patch('swirl')), isTrue);
    expect(engine.patches.instanceIdOf(patch('swirl')), isNotNull);
  });

  test(
    'a bound patch names its native instance for engine-direct addressing',
    () {
      final registry = registryWith({patch('swirl'): PatchPayload.empty});
      addTearDown(registry.dispose);

      engine.bindProject(registry);

      // End-to-end through the real engine wiring: opening the patch names its
      // native instance by the kind-stripped address, so a value published to
      // patcher.swirl.<slot> reaches it engine-direct (issue #318).
      final id = engine.patches.instanceIdOf(patch('swirl'))!;
      expect(patcher.instances[id]!.busName, 'swirl');
      expect(patcher.deliverToPatcherBus('patcher.swirl.0', 1), isTrue);
    },
  );

  test('start mounts the source on its placement bus, stop unmounts it', () {
    final registry = registryWith({
      mix('reverb'): const MixStrip(voice: 1),
      patch('src'): PatchPayload(placement: mix('reverb')),
    });
    addTearDown(registry.dispose);
    engine.bindProject(registry);

    // Loaded silent: placement persisted, but not running.
    expect(engine.patches.isRunning(patch('src')), isFalse);
    expect(patcher.mounted, isFalse);

    final started = engine.startPatchSource(patch('src'));
    expect(started, isTrue);
    expect(engine.patches.isRunning(patch('src')), isTrue);
    expect(patcher.mounted, isTrue);
    // Mounted on the reverb *user* bus (a non-null channel id), not master.
    final instanceId = engine.patches.instanceIdOf(patch('src'));
    expect(patcher.instances[instanceId]!.mountedBus, isNotNull);

    engine.stopPatchSource(patch('src'));
    expect(engine.patches.isRunning(patch('src')), isFalse);
    expect(patcher.mounted, isFalse);
  });

  test('flushPatchPayloads dumps the live patcher back into its entity', () {
    final registry = registryWith({patch('p'): PatchPayload.empty});
    addTearDown(registry.dispose);
    engine.bindProject(registry);

    // Edit the live native graph through the gateway (the surface's future seam).
    final id = engine.patches.instanceIdOf(patch('p'))!;
    patcher.createObject(id, Obj.dSine);

    engine.flushPatchPayloads();

    final payload = PatchPayload.fromJson(
      (registry.entityAt(patch('p'))!.payload! as Map).cast(),
    );
    // The fake dumps a structured, re-parseable graph: one object, no cables.
    expect(payload.dump['objects'], hasLength(1));
    expect(payload.dump['cables'], isEmpty);
  });

  test('a stale placement bus degrades into a surfaced notice', () {
    final registry = registryWith({
      // Placed on a bus that is not in the mix.
      patch('src'): PatchPayload(placement: mix('ghost')),
    });
    addTearDown(registry.dispose);
    engine.bindProject(registry);

    final started = engine.startPatchSource(patch('src'));

    expect(started, isFalse);
    expect(engine.patches.isRunning(patch('src')), isFalse);
    expect(patcher.mounted, isFalse);
    expect(engine.lastPatchNotice.value, isNotNull);
    expect(engine.lastPatchNotice.value!.bus, mix('ghost'));
  });

  test('a project swap tears the previous project\'s patchers down', () {
    final first = registryWith({patch('a'): PatchPayload.empty});
    addTearDown(first.dispose);
    engine.bindProject(first);
    final id = engine.patches.instanceIdOf(patch('a'));
    expect(patcher.instances.containsKey(id), isTrue);

    final second = registryWith({patch('b'): PatchPayload.empty});
    addTearDown(second.dispose);
    engine.bindProject(second);

    expect(engine.patches.isOpen(patch('a')), isFalse);
    expect(patcher.instances.containsKey(id), isFalse);
    expect(engine.patches.isOpen(patch('b')), isTrue);
  });
}
