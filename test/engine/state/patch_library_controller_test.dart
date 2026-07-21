import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/state/patch_bus_option.dart';
import 'package:phi/engine/state/patch_library_controller.dart';
import 'package:phi/engine/state/patch_placement_notice.dart';
import 'package:phi/engine/state/patch_reconciler.dart';

import '../test_doubles/fake_patcher_gateway.dart';

/// Unit coverage for the patcher **entity strip** controller (issue #224): the
/// tree over the `patch.` namespace, opening / switching patches over the
/// reconciler's per-entity instances (no leaks), the strip affordances (new /
/// duplicate / rename / delete / group / regroup / reorder), and source
/// placement + start / stop + placement persistence — all against the fake
/// gateway.
void main() {
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);
  EntityAddress patchIn(String group, String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [group, name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakePatcherGateway gateway;
  late ProjectRegistry registry;
  late PatchReconciler reconciler;
  late List<ProjectCommand> recorded;
  late List<PatchPlacementNotice> notices;

  // A resolver over a fixed bus map: an address present resolves to its channel
  // id (`null` = master), an absent one degrades (whole record `null`).
  final buses = <EntityAddress, int?>{mix('reverb'): 7, mix('master'): null};
  ({int? channelId})? resolve(EntityAddress address) =>
      buses.containsKey(address) ? (channelId: buses[address]) : null;

  List<PatchBusOption> busOptions() => [
    PatchBusOption(address: mix('master'), label: 'master'),
    PatchBusOption(address: mix('reverb'), label: 'reverb'),
  ];

  PatchLibraryController build() => PatchLibraryController(
    registry: registry,
    patches: reconciler,
    gateway: gateway,
    busOptions: busOptions,
    recordCommand: recorded.add,
  );

  setUp(() {
    gateway = FakePatcherGateway();
    registry = ProjectRegistry();
    recorded = [];
    notices = [];
    reconciler = PatchReconciler(
      gateway: gateway,
      resolveBus: resolve,
      onNotice: notices.add,
    );
  });

  tearDown(() => registry.dispose());

  group('tree', () {
    test('renders the patch namespace as an ordered forest', () {
      registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
      registry.createGroup(
        EntityAddress(kind: RegistryKinds.patch, segments: ['fx']),
      );
      registry.createEntity(
        patchIn('fx', 'b'),
        payload: PatchPayload.empty.toJson(),
      );
      final controller = build();
      addTearDown(controller.dispose);

      final tree = controller.tree;
      expect(tree.map((n) => n.name), ['a', 'fx']);
      final group = tree.firstWhere((n) => n.isGroup);
      expect(group.children.single.name, 'b');
      expect(controller.isEmpty, isFalse);
    });
  });

  group('open / switch (no instance leaks)', () {
    test('open binds an editor to the reconciler instance', () {
      registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
      final controller = build();
      addTearDown(controller.dispose);

      controller.open(patch('a'));

      expect(controller.openAddress, patch('a'));
      expect(
        controller.openEditor!.instanceId,
        reconciler.instanceIdOf(patch('a')),
      );
    });

    test('switching patches leaks no instances and preserves editors', () {
      registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
      registry.createEntity(patch('b'), payload: PatchPayload.empty.toJson());
      final controller = build();
      addTearDown(controller.dispose);

      controller.open(patch('a'));
      final editorA = controller.openEditor;
      controller.open(patch('b'));
      controller.open(patch('a'));

      // Two entities → exactly two native instances, no matter how often we
      // switch: the editor binds the reconciler's instance, never mints a new one.
      expect(gateway.instances, hasLength(2));
      // The cached editor survives the round-trip (same live graph on return).
      expect(identical(controller.openEditor, editorA), isTrue);
    });

    test('opening a group is a no-op', () {
      registry.createGroup(
        EntityAddress(kind: RegistryKinds.patch, segments: ['fx']),
      );
      final controller = build();
      addTearDown(controller.dispose);

      controller.open(
        EntityAddress(kind: RegistryKinds.patch, segments: ['fx']),
      );

      expect(controller.openAddress, isNull);
    });
  });

  group('strip affordances', () {
    test('newPatch creates an empty patch and opens it', () {
      final controller = build();
      addTearDown(controller.dispose);

      final address = controller.newPatch();

      expect(address, isNotNull);
      expect(registry.entityAt(address!), isNotNull);
      expect(controller.openAddress, address);
      expect(recorded, hasLength(1)); // journaled create
    });

    test(
      'duplicate copies the payload (dump + placement) and opens the copy',
      () {
        registry.createEntity(
          patch('src'),
          payload: PatchPayload(
            dump: const {'objects': 3},
            placement: mix('reverb'),
          ).toJson(),
        );
        final controller = build();
        addTearDown(controller.dispose);

        final copy = controller.duplicate(patch('src'));

        expect(copy, isNotNull);
        expect(copy!.name, 'src_copy');
        final payload = PatchPayload.fromJson(
          (registry.entityAt(copy)!.payload! as Map).cast(),
        );
        expect(payload.dump, const {'objects': 3});
        expect(payload.placement, mix('reverb'));
        expect(controller.openAddress, copy);
      },
    );

    test('newGroup creates a group folder', () {
      final controller = build();
      addTearDown(controller.dispose);

      final group = controller.newGroup();

      expect(registry.groupAt(group), isNotNull);
    });

    test('rename moves the open patch and re-opens it at the new address', () {
      registry.createEntity(patch('old'), payload: PatchPayload.empty.toJson());
      final controller = build();
      addTearDown(controller.dispose);
      controller.open(patch('old'));

      controller.rename(patch('old'), 'fresh');

      expect(registry.contains(patch('old')), isFalse);
      expect(registry.contains(patch('fresh')), isTrue);
      expect(controller.openAddress, patch('fresh'));
      // The reconciler re-materialised at the new address; the old instance went.
      expect(reconciler.isOpen(patch('fresh')), isTrue);
      expect(reconciler.isOpen(patch('old')), isFalse);
    });

    test(
      'delete removes the patch, tears its instance down, opens another',
      () {
        registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
        registry.createEntity(patch('b'), payload: PatchPayload.empty.toJson());
        final controller = build();
        addTearDown(controller.dispose);
        controller.open(patch('a'));
        expect(gateway.instances, hasLength(2));

        controller.delete(patch('a'));

        expect(registry.contains(patch('a')), isFalse);
        expect(reconciler.isOpen(patch('a')), isFalse);
        expect(gateway.instances, hasLength(1)); // a's native patcher torn down
        // The open patch went away → it falls back to the remaining one.
        expect(controller.openAddress, patch('b'));
      },
    );

    test('regroup re-parents a patch under a group', () {
      registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
      registry.createGroup(
        EntityAddress(kind: RegistryKinds.patch, segments: ['fx']),
      );
      final controller = build();
      addTearDown(controller.dispose);

      controller.regroup(
        patch('a'),
        EntityAddress(kind: RegistryKinds.patch, segments: ['fx']),
      );

      expect(registry.contains(patch('a')), isFalse);
      expect(registry.contains(patchIn('fx', 'a')), isTrue);
    });

    test('reorderBefore reorders within a section', () {
      registry.createEntity(patch('a'), payload: PatchPayload.empty.toJson());
      registry.createEntity(patch('b'), payload: PatchPayload.empty.toJson());
      registry.createEntity(patch('c'), payload: PatchPayload.empty.toJson());
      final controller = build();
      addTearDown(controller.dispose);

      controller.reorderBefore(patch('c'), patch('a'));

      expect(controller.tree.map((n) => n.name), ['c', 'a', 'b']);
    });
  });

  group('source placement + start / stop', () {
    setUp(() {
      registry.createEntity(patch('src'), payload: PatchPayload.empty.toJson());
    });

    test('place records the bus in the payload (persists) and syncs', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.open(patch('src'));

      controller.place(patch('src'), mix('reverb'));

      final payload = PatchPayload.fromJson(
        (registry.entityAt(patch('src'))!.payload! as Map).cast(),
      );
      expect(payload.placement, mix('reverb'));
      expect(controller.placementOf(patch('src')), mix('reverb'));
      // Journaled so save/undo carry it.
      expect(recorded.whereType<ProjectCommand>(), isNotEmpty);
    });

    test('start mounts the placed source, stop unmounts it', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.open(patch('src'));
      controller.place(patch('src'), mix('reverb'));
      final id = reconciler.instanceIdOf(patch('src'));

      final started = controller.start(patch('src'));
      expect(started, isTrue);
      expect(controller.isRunning(patch('src')), isTrue);
      expect(gateway.calls, contains('mountAsSource:$id:7:1.000'));

      controller.stop(patch('src'));
      expect(controller.isRunning(patch('src')), isFalse);
      expect(gateway.calls, contains('unmountSource:$id'));
    });

    test('an unplaced patch cannot start', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.open(patch('src'));

      expect(controller.start(patch('src')), isFalse);
      expect(controller.isRunning(patch('src')), isFalse);
    });

    test('unplace clears the placement', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.open(patch('src'));
      controller.place(patch('src'), mix('reverb'));

      controller.unplace(patch('src'));

      expect(controller.placementOf(patch('src')), isNull);
      final payload = PatchPayload.fromJson(
        (registry.entityAt(patch('src'))!.payload! as Map).cast(),
      );
      expect(payload.placement, isNull);
    });

    test('busOptions surfaces the injected buses', () {
      final controller = build();
      addTearDown(controller.dispose);

      expect(
        controller.busOptions().map((b) => b.label),
        containsAll(['master', 'reverb']),
      );
    });
  });
}
