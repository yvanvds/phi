import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/commands/reorder_child_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/recovery/registry_command_codec.dart';

void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  List<String> childrenOf(ProjectRegistry registry, String group) =>
      registry.childrenOfGroup(addr(group)).map((n) => n.name).toList();

  List<String> topOf(ProjectRegistry registry, String kind) =>
      registry.childrenOfKind(kind).map((n) => n.name).toList();

  ProjectRegistry drumsWith(List<String> children) {
    final registry = ProjectRegistry()..createGroup(addr('mix.drums'));
    for (final name in children) {
      registry.createEntity(addr('mix.drums.$name'));
    }
    return registry;
  }

  group('ProjectRegistry.reorderChild', () {
    test('moves a child to a new index within its group', () {
      final registry = drumsWith(['kick', 'snare', 'hat']);
      addTearDown(registry.dispose);

      registry.reorderChild(
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'hat',
        index: 0,
      );

      expect(childrenOf(registry, 'mix.drums'), ['hat', 'kick', 'snare']);
    });

    test('reorders top-level children when group is null', () {
      final registry = ProjectRegistry()
        ..createEntity(addr('mix.a'))
        ..createEntity(addr('mix.b'))
        ..createEntity(addr('mix.c'));
      addTearDown(registry.dispose);

      registry.reorderChild(kind: 'mix', group: null, childName: 'a', index: 2);

      expect(topOf(registry, 'mix'), ['b', 'c', 'a']);
    });

    test('clamps an out-of-range index and is a no-op for a missing child', () {
      final registry = drumsWith(['kick', 'snare']);
      addTearDown(registry.dispose);

      registry.reorderChild(
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'kick',
        index: 99,
      );
      expect(childrenOf(registry, 'mix.drums'), ['snare', 'kick']);

      var notified = 0;
      registry.addListener(() => notified++);
      registry.reorderChild(
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'gone',
        index: 0,
      );
      expect(notified, 0); // no-op does not notify
    });

    test('notifies but emits no lifecycle event (order is not namespace)', () {
      final registry = drumsWith(['kick', 'snare']);
      addTearDown(registry.dispose);
      var notified = 0;
      registry.addListener(() => notified++);
      final events = <Object>[];
      final sub = registry.events.listen(events.add);
      addTearDown(sub.cancel);

      registry.reorderChild(
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'snare',
        index: 0,
      );

      expect(notified, 1);
      expect(events, isEmpty);
    });
  });

  group('ReorderChildCommand', () {
    test('apply moves to toIndex; revert restores fromIndex', () {
      final registry = drumsWith(['kick', 'snare', 'hat']);
      addTearDown(registry.dispose);

      final command = ReorderChildCommand(
        registry,
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'hat',
        fromIndex: 2,
        toIndex: 0,
      );

      command.apply();
      expect(childrenOf(registry, 'mix.drums'), ['hat', 'kick', 'snare']);

      command.revert();
      expect(childrenOf(registry, 'mix.drums'), ['kick', 'snare', 'hat']);
    });

    test('touches the reordered child address', () {
      final registry = drumsWith(['kick', 'snare']);
      addTearDown(registry.dispose);
      final command = ReorderChildCommand(
        registry,
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'snare',
        fromIndex: 1,
        toIndex: 0,
      );
      expect(command.entitiesTouched, {addr('mix.drums.snare')});
    });

    test('toJson is JSON-shaped for the journal', () {
      final registry = drumsWith(['kick', 'snare']);
      addTearDown(registry.dispose);
      final json = ReorderChildCommand(
        registry,
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'snare',
        fromIndex: 1,
        toIndex: 0,
      ).toJson();
      expect(json['type'], 'reorder_child');
      expect(json['kind'], 'mix');
      expect(json['group'], 'mix.drums');
      expect(json['child'], 'snare');
      expect(json['from'], 1);
      expect(json['to'], 0);
    });

    test('top-level command omits the group key', () {
      final registry = ProjectRegistry()
        ..createEntity(addr('mix.a'))
        ..createEntity(addr('mix.b'));
      addTearDown(registry.dispose);
      final json = ReorderChildCommand(
        registry,
        kind: 'mix',
        group: null,
        childName: 'a',
        fromIndex: 0,
        toIndex: 1,
      ).toJson();
      expect(json.containsKey('group'), isFalse);
    });
  });

  group('RegistryCommandCodec reorder_child', () {
    const codec = RegistryCommandCodec();

    test('decodes and replays a grouped reorder', () {
      final journaled = ReorderChildCommand(
        ProjectRegistry(),
        kind: 'mix',
        group: addr('mix.drums'),
        childName: 'hat',
        fromIndex: 2,
        toIndex: 0,
      ).toJson();

      final registry = drumsWith(['kick', 'snare', 'hat']);
      addTearDown(registry.dispose);
      codec.decode(journaled, registry).apply();

      expect(childrenOf(registry, 'mix.drums'), ['hat', 'kick', 'snare']);
    });

    test('decodes a top-level reorder (no group key)', () {
      final journaled = ReorderChildCommand(
        ProjectRegistry(),
        kind: 'mix',
        group: null,
        childName: 'a',
        fromIndex: 0,
        toIndex: 1,
      ).toJson();

      final registry = ProjectRegistry()
        ..createEntity(addr('mix.a'))
        ..createEntity(addr('mix.b'));
      addTearDown(registry.dispose);
      codec.decode(journaled, registry).apply();

      expect(topOf(registry, 'mix'), ['b', 'a']);
    });
  });
}
