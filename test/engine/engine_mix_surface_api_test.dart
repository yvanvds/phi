import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/mix_tree_node.dart';
import 'package:phi/engine/state/mixer_channel.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// The Mix-surface tree-editing façade (issue #169): [PhiEngine.addGroup] /
/// [PhiEngine.addReturn], drag re-parenting ([moveChannelToGroup]) and section
/// reorder ([moveChannelBefore]), and the [mixTree] view the grouped rack
/// renders — all against the fake gateway.
void main() {
  EntityAddress mix(List<String> segments) =>
      EntityAddress(kind: RegistryKinds.mix, segments: segments);

  late FakeYseGateway gateway;
  late PhiEngine engine;
  late List<ProjectCommand> recorded;

  setUp(() {
    gateway = FakeYseGateway();
    engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    engine.start();
    recorded = [];
    engine.bindProject(engine.mixRegistry, recordCommand: recorded.add);
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  List<String> childrenOf(String group) => engine.mixRegistry
      .childrenOfGroup(mix([group]))
      .map((n) => n.name)
      .toList();

  group('addGroup', () {
    test('materialises a group bus in the tree and records the create', () {
      final group = engine.addGroup(name: 'drums');

      expect(group.name, 'drums');
      expect(engine.mixTree.value, hasLength(1));
      expect(engine.mixTree.value.single.isGroup, isTrue);
      expect(engine.mixTree.value.single.channel, same(group));
      expect(engine.mixRegistry.groupAt(mix(['drums'])), isNotNull);
      expect(recorded, hasLength(1));
    });
  });

  group('addReturn', () {
    test('creates a return bus outside the tree', () {
      final ret = engine.addReturn(name: 'verb');

      expect(engine.returns.value, [ret]);
      expect(engine.mixTree.value, isEmpty);
      final entity = engine.mixRegistry.entityAt(mix(['verb']))!;
      expect(
        MixStrip.fromJson((entity.payload! as Map).cast()).isReturn,
        isTrue,
      );
    });
  });

  group('moveChannelToGroup', () {
    test('re-parents a top-level strip into a group (registry + tree)', () {
      final group = engine.addGroup(name: 'drums');
      final kick = engine.addChannel(name: 'kick');

      engine.moveChannelToGroup(kick, _addressOf(engine, group));

      expect(engine.mixRegistry.contains(mix(['kick'])), isFalse);
      expect(childrenOf('drums'), ['kick']);
      // The tree nests kick under drums.
      final drumsNode = engine.mixTree.value.single;
      expect(drumsNode.children.map((c) => c.channel.name), ['kick']);
    });

    test('null group moves a grouped strip back to the top level', () {
      final group = engine.addGroup(name: 'drums');
      final kick = engine.addChannel(name: 'kick');
      engine.moveChannelToGroup(kick, _addressOf(engine, group));
      expect(childrenOf('drums'), ['kick']);

      // The channel handle survives the reparent (moveChannel, not rebuild), so
      // re-read it from the tree before moving it back out.
      final kickNode = engine.mixTree.value.single.children.single;
      engine.moveChannelToGroup(kickNode.channel, null);

      expect(engine.mixRegistry.contains(mix(['kick'])), isTrue);
      expect(childrenOf('drums'), isEmpty);
    });

    test('a strip already directly under the target is a no-op', () {
      final group = engine.addGroup(name: 'drums');
      final kick = engine.addChannel(name: 'kick');
      engine.moveChannelToGroup(kick, _addressOf(engine, group));
      recorded.clear();

      final kickNode = engine.mixTree.value.single.children.single;
      engine.moveChannelToGroup(kickNode.channel, _addressOf(engine, group));

      expect(recorded, isEmpty);
      expect(childrenOf('drums'), ['kick']);
    });
  });

  group('moveChannelBefore', () {
    test('reorders two siblings within a group', () {
      final group = engine.addGroup(name: 'drums');
      final groupAddr = _addressOf(engine, group);
      final kick = engine.addChannel(name: 'kick');
      final snare = engine.addChannel(name: 'snare');
      engine.moveChannelToGroup(kick, groupAddr);
      engine.moveChannelToGroup(snare, groupAddr);
      expect(childrenOf('drums'), ['kick', 'snare']);

      final children = engine.mixTree.value.single.children;
      final kickNode = children.firstWhere((c) => c.channel.name == 'kick');
      final snareNode = children.firstWhere((c) => c.channel.name == 'snare');
      engine.moveChannelBefore(snareNode.channel, kickNode.channel);

      expect(childrenOf('drums'), ['snare', 'kick']);
    });

    test('different-parent channels are not reordered', () {
      final group = engine.addGroup(name: 'drums');
      final kick = engine.addChannel(name: 'kick');
      engine.moveChannelToGroup(kick, _addressOf(engine, group));
      final lead = engine.addChannel(name: 'lead'); // top-level
      recorded.clear();

      final drumsNode = engine.mixTree.value.firstWhere((n) => n.isGroup);
      final kickNode = drumsNode.children.single;
      engine.moveChannelBefore(lead, kickNode.channel);

      expect(recorded, isEmpty); // cross-parent → no reorder
    });
  });

  group('group bus state', () {
    test('setChannelVolume on a group persists to the group payload', () {
      final group = engine.addGroup(name: 'drums');

      engine.setChannelVolume(group, 0.5);

      final payload = engine.mixRegistry.groupAt(mix(['drums']))!.payload;
      final strip = MixStrip.fromJson((payload! as Map).cast());
      expect(strip.volume, 0.5);
    });
  });
}

EntityAddress _addressOf(PhiEngine engine, MixerChannel channel) {
  EntityAddress? found;
  void walk(List<MixTreeNode> nodes) {
    for (final node in nodes) {
      if (identical(node.channel, channel)) found = node.address;
      walk(node.children);
    }
  }

  walk(engine.mixTree.value);
  return found!;
}
