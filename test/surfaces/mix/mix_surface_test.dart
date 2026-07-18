import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/mix_tree_node.dart';
import 'package:phi/engine/state/mixer_channel.dart';
import 'package:phi/surfaces/mix/mix_surface.dart';

import '../../engine/test_doubles/fake_yse_gateway.dart';

void main() {
  group('MixSurface', () {
    late FakeYseGateway gateway;
    late PhiEngine engine;

    setUp(() {
      gateway = FakeYseGateway();
      engine = PhiEngine(
        gateway,
        telemetryInterval: const Duration(milliseconds: 50),
      );
      engine.start();
    });

    tearDown(() async {
      await engine.dispose();
      await gateway.dispose();
    });

    EntityAddress mix(List<String> segments) =>
        EntityAddress(kind: RegistryKinds.mix, segments: segments);

    Future<void> pumpSurface(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MixSurface(engine: engine)),
      ),
    );

    /// Opens the header `+` menu and picks [item] (e.g. 'add group').
    Future<void> pickFromAddMenu(WidgetTester tester, String item) async {
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    /// Canonical drag-and-drop: grab [source] and drop it on [target].
    Future<void> dragOnto(
      WidgetTester tester,
      Finder source,
      Finder target,
    ) async {
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Finder stripFor(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ChannelStrip));

    testWidgets('renders the master strip on first frame', (tester) async {
      await pumpSurface(tester);

      expect(find.byType(ChannelStrip), findsOneWidget);
      expect(find.text('master'), findsOneWidget);
    });

    testWidgets('the add menu offers channel, group and return', (
      tester,
    ) async {
      await pumpSurface(tester);

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      expect(find.text('add channel'), findsOneWidget);
      expect(find.text('add group'), findsOneWidget);
      expect(find.text('add return'), findsOneWidget);
    });

    testWidgets('add channel from the menu adds a user strip', (tester) async {
      await pumpSurface(tester);

      await pickFromAddMenu(tester, 'add channel');

      expect(find.byType(ChannelStrip), findsNWidgets(2)); // + master
      expect(engine.channels.value, hasLength(1));
    });

    testWidgets('add group from the menu adds a framed group bus', (
      tester,
    ) async {
      await pumpSurface(tester);

      await pickFromAddMenu(tester, 'add group');

      // A group bus is a non-return channel, so it surfaces in the tree as a
      // group node and in the flat channel list.
      expect(engine.mixTree.value, hasLength(1));
      expect(engine.mixTree.value.single.isGroup, isTrue);
      expect(engine.channels.value, hasLength(1));
      expect(find.byType(ChannelStrip), findsNWidgets(2)); // bus + master
    });

    testWidgets('add return from the menu lands outside the rack', (
      tester,
    ) async {
      await pumpSurface(tester);

      await pickFromAddMenu(tester, 'add return');

      // Returns sit outside the tree — no rack strip, one return bus.
      expect(engine.returns.value, hasLength(1));
      expect(engine.mixTree.value, isEmpty);
      expect(engine.channels.value, isEmpty);
      expect(find.byType(ChannelStrip), findsOneWidget); // master only
    });

    testWidgets('channel count in the header reflects user channels', (
      tester,
    ) async {
      await pumpSurface(tester);

      expect(find.text('MIX · 1 CHANNELS'), findsOneWidget);

      await pickFromAddMenu(tester, 'add channel');
      await pickFromAddMenu(tester, 'add channel');

      expect(find.text('MIX · 3 CHANNELS'), findsOneWidget);
    });

    testWidgets('the master strip has no remove control', (tester) async {
      await pumpSurface(tester);

      expect(find.byType(ChannelStrip), findsOneWidget);
      expect(find.byKey(ChannelStrip.removeButtonKey), findsNothing);
    });

    testWidgets('removing a user strip drops it from the rack', (tester) async {
      await pumpSurface(tester);
      await pickFromAddMenu(tester, 'add channel');
      expect(engine.channels.value, hasLength(1));

      await tester.tap(find.byKey(ChannelStrip.removeButtonKey));
      await tester.pump();

      expect(engine.channels.value, isEmpty);
      expect(find.byType(ChannelStrip), findsOneWidget); // master only
    });

    testWidgets('inline-renaming a user strip renames the channel', (
      tester,
    ) async {
      await pumpSurface(tester);
      await pickFromAddMenu(tester, 'add channel');
      expect(engine.channels.value.single.name, 'ch_1');

      await tester.tap(find.text('ch_1'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'lead');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(engine.channels.value.single.name, 'lead');
      expect(find.text('lead'), findsOneWidget);
    });

    testWidgets('a group renders its child strips inside the section', (
      tester,
    ) async {
      // Build a group with one child through the engine, then render.
      final group = engine.addGroup(name: 'drums');
      final kick = engine.addChannel(name: 'kick');
      engine.moveChannelToGroup(kick, _addressOf(engine, group));
      await pumpSurface(tester);

      final tree = engine.mixTree.value;
      expect(tree, hasLength(1));
      expect(tree.single.isGroup, isTrue);
      expect(tree.single.children.map((c) => c.channel.name), ['kick']);
      // The bus header and the child strip both render (+ master).
      expect(find.text('drums'), findsOneWidget);
      expect(find.text('kick'), findsOneWidget);
      expect(find.byType(ChannelStrip), findsNWidgets(3));
    });

    testWidgets('dragging a strip onto a group re-parents it in the registry', (
      tester,
    ) async {
      engine.addGroup(name: 'drums');
      engine.addChannel(name: 'kick'); // top-level
      await pumpSurface(tester);

      // kick starts at top level.
      expect(engine.mixRegistry.contains(mix(['kick'])), isTrue);
      expect(engine.mixRegistry.childrenOfGroup(mix(['drums'])), isEmpty);

      // Drag kick's handle onto the group's header strip.
      await dragOnto(
        tester,
        find.byKey(MixSurface.dragHandleKey('kick')),
        stripFor('drums'),
      );

      // kick is now a child of drums — the move is reflected in the registry.
      expect(engine.mixRegistry.contains(mix(['kick'])), isFalse);
      expect(
        engine.mixRegistry.childrenOfGroup(mix(['drums'])).map((n) => n.name),
        ['kick'],
      );
    });

    testWidgets('dragging a grouped strip onto the rack un-groups it', (
      tester,
    ) async {
      final group = engine.addGroup(name: 'drums');
      final kick = engine.addChannel(name: 'kick');
      engine.moveChannelToGroup(kick, _addressOf(engine, group));
      await pumpSurface(tester);
      expect(engine.mixRegistry.contains(mix(['drums', 'kick'])), isTrue);

      // Drop kick onto the open rack (the master strip area falls through to the
      // rack's move-to-top target).
      await dragOnto(
        tester,
        find.byKey(MixSurface.dragHandleKey('kick')),
        stripFor('master'),
      );

      expect(engine.mixRegistry.contains(mix(['drums', 'kick'])), isFalse);
      expect(engine.mixRegistry.contains(mix(['kick'])), isTrue);
    });

    testWidgets('reordering within a group persists the new child order', (
      tester,
    ) async {
      final group = engine.addGroup(name: 'drums');
      final groupAddr = _addressOf(engine, group);
      final kick = engine.addChannel(name: 'kick');
      final snare = engine.addChannel(name: 'snare');
      engine.moveChannelToGroup(kick, groupAddr);
      engine.moveChannelToGroup(snare, groupAddr);
      await pumpSurface(tester);
      expect(
        engine.mixRegistry.childrenOfGroup(mix(['drums'])).map((n) => n.name),
        ['kick', 'snare'],
      );

      // Drag snare before kick — the registry child order (what persists to
      // _group.json) flips.
      await dragOnto(
        tester,
        find.byKey(MixSurface.dragHandleKey('snare')),
        stripFor('kick'),
      );

      expect(
        engine.mixRegistry.childrenOfGroup(mix(['drums'])).map((n) => n.name),
        ['snare', 'kick'],
      );
    });
  });
}

/// The registry address the engine minted for [channel] — read back off the
/// mix tree by identity, so tests can pass a group address to `moveChannelToGroup`.
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
