import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_event.dart';

/// The fine-grained lifecycle stream the `RegistryMirror` seam (design §8)
/// consumes: every structural mutation emits exactly one create / move / delete
/// event, in the address vocabulary the mirror needs.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late ProjectRegistry registry;
  late List<RegistryEvent> events;

  setUp(() {
    registry = ProjectRegistry();
    events = [];
    final sub = registry.events.listen(events.add);
    addTearDown(sub.cancel);
    addTearDown(registry.dispose);
  });

  test('createEntity emits one RegistryEntityCreated', () async {
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();

    expect(events, [RegistryEntityCreated(addr('clip.lead'))]);
  });

  test('createGroup emits a create, and is silent when idempotent', () async {
    registry.createGroup(addr('clip.drums'));
    registry.createGroup(addr('clip.drums')); // already there — no notify.
    await pumpEventQueue();

    expect(events, [RegistryEntityCreated(addr('clip.drums'))]);
  });

  test('remove emits one RegistryEntityDeleted', () async {
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();
    events.clear();

    registry.remove(addr('clip.lead'));
    await pumpEventQueue();

    expect(events, [RegistryEntityDeleted(addr('clip.lead'))]);
  });

  test('removing a missing node is silent', () async {
    registry.remove(addr('clip.ghost'));
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('a same-group rename emits Moved with both addresses', () async {
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();
    events.clear();

    registry.move(addr('clip.lead'), addr('clip.melody'));
    await pumpEventQueue();

    expect(events, [
      RegistryEntityMoved(addr('clip.lead'), addr('clip.melody')),
    ]);
  });

  test('a regroup emits Moved with the new parent path', () async {
    registry.createEntity(addr('clip.lead'));
    registry.createGroup(addr('clip.solos'));
    await pumpEventQueue();
    events.clear();

    registry.move(addr('clip.lead'), addr('clip.solos.lead'));
    await pumpEventQueue();

    expect(events, [
      RegistryEntityMoved(addr('clip.lead'), addr('clip.solos.lead')),
    ]);
  });

  test('a no-op move (same address) emits nothing', () async {
    registry.createEntity(addr('clip.lead'));
    await pumpEventQueue();
    events.clear();

    registry.move(addr('clip.lead'), addr('clip.lead'));
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('setReferences changes edges, not the namespace — no event', () async {
    registry.createEntity(addr('mix.perc'));
    registry.createEntity(addr('voice.bells'));
    await pumpEventQueue();
    events.clear();

    registry.setReferences(addr('voice.bells'), {addr('mix.perc')});
    await pumpEventQueue();

    expect(events, isEmpty);
  });
}
