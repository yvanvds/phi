import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/engine/bridge/no_op_registry_mirror.dart';
import 'package:phi/engine/bridge/registry_mirror_binder.dart';

import '../test_doubles/recording_registry_mirror.dart';

/// The binder is the adapter that proves "registry lifecycle events reach the
/// mirror" (issue #125): it forwards each event and classifies a move into a
/// rename (same parent group) or a regroup (new parent).
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late RecordingRegistryMirror spy;
  late RegistryMirrorBinder binder;
  late ProjectRegistry registry;

  setUp(() {
    spy = RecordingRegistryMirror();
    binder = RegistryMirrorBinder(spy);
    registry = ProjectRegistry();
    addTearDown(binder.dispose);
    addTearDown(registry.dispose);
  });

  test('create reaches the mirror as onCreate', () async {
    binder.bind(registry);

    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();

    expect(spy.creates, [addr('clip.lead')]);
    expect(binder.boundRegistry, same(registry));
  });

  test('delete reaches the mirror as onDelete', () async {
    binder.bind(registry);
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();

    registry.remove(addr('clip.lead'));
    await pumpEventQueue();

    expect(spy.deletes, [addr('clip.lead')]);
  });

  test('a same-group move is classified as a rename', () async {
    binder.bind(registry);
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();

    registry.move(addr('clip.lead'), addr('clip.melody'));
    await pumpEventQueue();

    expect(spy.renames, [(addr('clip.lead'), addr('clip.melody'))]);
    expect(spy.regroups, isEmpty);
  });

  test('a nested same-group rename is still a rename', () async {
    binder.bind(registry);
    registry.createEntity(addr('clip.solos.lead'));
    await pumpEventQueue();

    registry.move(addr('clip.solos.lead'), addr('clip.solos.melody'));
    await pumpEventQueue();

    expect(spy.renames, [(addr('clip.solos.lead'), addr('clip.solos.melody'))]);
    expect(spy.regroups, isEmpty);
  });

  test('a move to a new parent group is classified as a regroup', () async {
    binder.bind(registry);
    registry.createEntity(addr('clip.lead'));
    registry.createGroup(addr('clip.solos'));
    await pumpEventQueue();

    registry.move(addr('clip.lead'), addr('clip.solos.lead'));
    await pumpEventQueue();

    expect(spy.regroups, [(addr('clip.lead'), addr('clip.solos.lead'))]);
    expect(spy.renames, isEmpty);
  });

  test('rebinding a new registry stops forwarding the old one', () async {
    final other = ProjectRegistry();
    addTearDown(other.dispose);

    binder.bind(registry);
    binder.bind(other);
    expect(binder.boundRegistry, same(other));

    // The abandoned registry no longer reaches the mirror...
    registry.createEntity(addr('clip.stale'));
    await pumpEventQueue();
    expect(spy.creates, isEmpty);

    // ...while the newly bound one does.
    other.createEntity(addr('clip.fresh'));
    await pumpEventQueue();
    expect(spy.creates, [addr('clip.fresh')]);
  });

  test(
    'binding the same registry twice is a no-op (no double delivery)',
    () async {
      binder.bind(registry);
      binder.bind(registry);

      registry.createEntity(addr('clip.lead'));
      await pumpEventQueue();

      expect(spy.creates, [addr('clip.lead')]);
    },
  );

  test('resync full-syncs every node across kinds, parents first', () async {
    binder.bind(registry);
    registry.createEntity(addr('clip.drums.intro_fill'));
    registry.createEntity(addr('voice.bells'));
    await pumpEventQueue();

    binder.resync();

    // One full sync, listing the group before its child and covering both kinds.
    expect(spy.fullSyncs, hasLength(1));
    expect(spy.fullSyncs.single, [
      addr('clip.drums'),
      addr('clip.drums.intro_fill'),
      addr('voice.bells'),
    ]);
  });

  test('resync before any bind is a no-op', () async {
    binder.resync();
    expect(spy.fullSyncs, isEmpty);
  });

  test('resync after dispose is a no-op', () async {
    binder.bind(registry);
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();
    binder.dispose();

    binder.resync();

    expect(spy.fullSyncs, isEmpty);
  });

  test('dispose detaches: later events do not reach the mirror', () async {
    binder.bind(registry);
    binder.dispose();
    expect(binder.boundRegistry, isNull);

    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();

    expect(spy.creates, isEmpty);
  });

  test(
    'NoOpRegistryMirror drops every notification without throwing',
    () async {
      final noop = RegistryMirrorBinder(const NoOpRegistryMirror());
      addTearDown(noop.dispose);
      noop.bind(registry);

      registry.createEntity(addr('clip.lead'));
      registry.move(addr('clip.lead'), addr('clip.melody'));
      registry.remove(addr('clip.melody'));
      noop.resync();

      await expectLater(pumpEventQueue(), completes);
    },
  );
}
