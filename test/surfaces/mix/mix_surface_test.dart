import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/channel_strip/channel_strip.dart';
import 'package:phi/design/widgets/dialog/delete_impact_dialog.dart';
import 'package:phi/design/widgets/select/phi_select.dart';
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

      // Returns sit outside the tree — not in the rack, not a user channel —
      // but they now render as strips inside the returns section beside master.
      expect(engine.returns.value, hasLength(1));
      expect(engine.mixTree.value, isEmpty);
      expect(engine.channels.value, isEmpty);
      expect(find.byKey(MixSurface.returnsSectionKey), findsOneWidget);
      expect(find.byType(ChannelStrip), findsNWidgets(2)); // return + master
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

    // ── Sends (design §4) ────────────────────────────────────────────────────

    /// Opens the picker keyed [pickerKey] and taps the [returnName] option. The
    /// option is scoped to the picker's own subtree — its `OverlayPortal` keeps
    /// the open menu there — so it never collides with the same return name shown
    /// in the returns-section strip. `.last` skips the closed control when a
    /// target picker already shows the name.
    Future<void> pickReturn(
      WidgetTester tester,
      Key pickerKey,
      String returnName,
    ) async {
      await tester.tap(find.byKey(pickerKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(pickerKey),
              matching: find.text(returnName),
            )
            .last,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('picking a return from the add-send row creates a send', (
      tester,
    ) async {
      final kick = engine.addChannel(name: 'kick');
      engine.addReturn(name: 'verb');
      await pumpSurface(tester);
      expect(engine.channelSends(kick), isEmpty);

      await pickReturn(tester, MixSurface.addSendKey('kick'), 'verb');

      final sends = engine.channelSends(kick);
      expect(sends, hasLength(1));
      expect(sends.single.to, mix(['verb']));
      expect(sends.single.level, 1.0);
      expect(sends.single.preFader, isFalse);
      // The new send now renders its own row.
      expect(find.byKey(MixSurface.sendTargetKey('kick', 0)), findsOneWidget);
    });

    testWidgets('the send target picker offers only returns', (tester) async {
      engine.addChannel(name: 'kick');
      engine.addChannel(name: 'bass');
      engine.addGroup(name: 'drums');
      engine.addReturn(name: 'verb');
      await pumpSurface(tester);

      final picker = tester.widget<PhiSelect<MixerChannel>>(
        find.byKey(MixSurface.addSendKey('kick')),
      );
      final labels = [
        for (final g in picker.groups) ...g.options.map((o) => o.label),
      ];
      // Only the return — never a plain channel, a group bus, or master.
      expect(labels, ['verb']);
    });

    testWidgets('editing a send target rewires the slot', (tester) async {
      final kick = engine.addChannel(name: 'kick');
      final verb = engine.addReturn(name: 'verb');
      engine.addReturn(name: 'delay');
      engine.setChannelSend(kick, 0, returnBus: verb, level: 0.5);
      await pumpSurface(tester);
      expect(engine.channelSends(kick).single.to, mix(['verb']));

      await pickReturn(tester, MixSurface.sendTargetKey('kick', 0), 'delay');

      final send = engine.channelSends(kick).single;
      expect(send.to, mix(['delay']));
      // Level and pre/post survive the target rewire.
      expect(send.level, 0.5);
      expect(send.preFader, isFalse);
    });

    testWidgets('toggling pre/post flips the send and back', (tester) async {
      final kick = engine.addChannel(name: 'kick');
      final verb = engine.addReturn(name: 'verb');
      engine.setChannelSend(kick, 0, returnBus: verb, level: 0.5);
      await pumpSurface(tester);
      expect(engine.channelSends(kick).single.preFader, isFalse);

      await tester.tap(find.byKey(MixSurface.sendPrePostKey('kick', 0)));
      await tester.pump();
      expect(engine.channelSends(kick).single.preFader, isTrue);

      await tester.tap(find.byKey(MixSurface.sendPrePostKey('kick', 0)));
      await tester.pump();
      expect(engine.channelSends(kick).single.preFader, isFalse);
    });

    testWidgets('removing a send clears its slot', (tester) async {
      final kick = engine.addChannel(name: 'kick');
      final verb = engine.addReturn(name: 'verb');
      engine.setChannelSend(kick, 0, returnBus: verb, level: 0.5);
      await pumpSurface(tester);
      expect(engine.channelSends(kick), hasLength(1));

      await tester.tap(find.byKey(MixSurface.sendRemoveKey('kick', 0)));
      await tester.pump();

      expect(engine.channelSends(kick), isEmpty);
      expect(find.byKey(MixSurface.sendTargetKey('kick', 0)), findsNothing);
    });

    testWidgets('a send-level drag coalesces to a single command', (
      tester,
    ) async {
      // Record every command; the coalescing contract is one command per drag.
      final commands = <Object>[];
      engine.bindProject(engine.mixRegistry, recordCommand: commands.add);
      final kick = engine.addChannel(name: 'kick');
      final verb = engine.addReturn(name: 'verb');
      engine.setChannelSend(kick, 0, returnBus: verb, level: 0.8);
      await pumpSurface(tester);
      expect(engine.channelSends(kick), hasLength(1));

      // Only count the drag itself.
      commands.clear();
      gateway.calls.clear();
      final fader = find.byKey(MixSurface.sendLevelKey('kick', 0));
      final gesture = await tester.startGesture(tester.getCenter(fader));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20)); // down → lower the level
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // One journaled payload command for the whole drag …
      expect(commands, hasLength(1));
      // … the gateway was rammed live several times during it …
      expect(
        gateway.calls.where((c) => c.startsWith('setSendLevel:')).length,
        greaterThan(1),
      );
      // … and the level actually dropped from its 0.8 start.
      expect(engine.channelSends(kick).single.level, lessThan(0.8));
    });

    testWidgets('a group bus header also gains a sends area', (tester) async {
      final group = engine.addGroup(name: 'drums');
      engine.addReturn(name: 'verb');
      await pumpSurface(tester);
      // The bus header strip carries an add-send picker too (design §4).
      expect(find.byKey(MixSurface.addSendKey('drums')), findsOneWidget);

      await pickReturn(tester, MixSurface.addSendKey('drums'), 'verb');

      // The send persists on the group bus's own payload.
      expect(engine.channelSends(group), hasLength(1));
      expect(engine.channelSends(group).single.to, mix(['verb']));
    });

    // ── Returns section (design §4, §5) ──────────────────────────────────────

    testWidgets('returns render in the section without a solo button', (
      tester,
    ) async {
      engine.addReturn(name: 'verb');
      engine.addReturn(name: 'delay');
      await pumpSurface(tester);

      final section = find.byKey(MixSurface.returnsSectionKey);
      expect(section, findsOneWidget);
      // Both return strips render inside the section.
      expect(
        find.descendant(of: section, matching: find.byType(ChannelStrip)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: section, matching: find.text('verb')),
        findsOneWidget,
      );

      // Returns are exempt from solo (design §5) — a mute button, but no solo.
      final verbStrip = find.ancestor(
        of: find.text('verb'),
        matching: find.byType(ChannelStrip),
      );
      expect(
        find.descendant(of: verbStrip, matching: find.text('M')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: verbStrip, matching: find.text('S')),
        findsNothing,
      );
    });

    // ── Layout-aware master meters (design §6) ───────────────────────────────
    //
    // The per-output meters are telemetry-driven, and the engine's telemetry
    // timer only fires under `tester.pump` when it is created inside the test's
    // fake-async zone — so these tests build their own engine in the body rather
    // than reuse the setUp engine (whose timer lives outside the zone).

    /// Runs [body] against a started engine + gateway created **in the test
    /// body** (so its telemetry timer is a fake timer that fires under `pump`),
    /// disposing both in a `finally` — the timer must be cancelled before the
    /// body returns or the fake-async pending-timer invariant trips.
    Future<void> withMeteredSurface(
      WidgetTester tester,
      Future<void> Function(PhiEngine engine, FakeYseGateway gateway) body,
    ) async {
      final g = FakeYseGateway();
      final e = PhiEngine(
        g,
        telemetryInterval: const Duration(milliseconds: 20),
      );
      e.start();
      try {
        await body(e, g);
      } finally {
        await e.dispose();
        await g.dispose();
      }
    }

    /// Advances the telemetry timer and settles the rebuild so the master strip
    /// picks up the gateway's current output count + per-output peaks.
    Future<void> tickTelemetry(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
    }

    testWidgets('the master strip shows one meter bar per output — stereo', (
      tester,
    ) async {
      await withMeteredSurface(tester, (engine, gateway) async {
        // The fake gateway defaults to a stereo master (two outputs).
        gateway.masterOutputCountValue = 2;
        gateway.masterPeakOutputs = [0.3, 0.7];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MixSurface(engine: engine)),
          ),
        );
        await tickTelemetry(tester);

        // Exactly two bars — derived from the live output count, not hard-coded.
        expect(find.byKey(ChannelStrip.outputMeterKey(0)), findsOneWidget);
        expect(find.byKey(ChannelStrip.outputMeterKey(1)), findsOneWidget);
        expect(find.byKey(ChannelStrip.outputMeterKey(2)), findsNothing);
      });
    });

    testWidgets('the master meter re-derives its bar count on a 5.1 layout', (
      tester,
    ) async {
      await withMeteredSurface(tester, (engine, gateway) async {
        // Start stereo …
        gateway.masterOutputCountValue = 2;
        gateway.masterPeakOutputs = [0.2, 0.4];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MixSurface(engine: engine)),
          ),
        );
        await tickTelemetry(tester);
        expect(find.byKey(ChannelStrip.outputMeterKey(1)), findsOneWidget);
        expect(find.byKey(ChannelStrip.outputMeterKey(2)), findsNothing);

        // … then the device/layout swaps to 5.1 (six outputs) at runtime. The
        // next telemetry tick re-derives the bar count without a restart.
        gateway.masterOutputCountValue = 6;
        gateway.masterPeakOutputs = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
        await tickTelemetry(tester);

        for (var i = 0; i < 6; i++) {
          expect(find.byKey(ChannelStrip.outputMeterKey(i)), findsOneWidget);
        }
        expect(find.byKey(ChannelStrip.outputMeterKey(6)), findsNothing);
      });
    });

    testWidgets('user strips keep a single meter — no per-output bars', (
      tester,
    ) async {
      await withMeteredSurface(tester, (engine, gateway) async {
        final kick = engine.addChannel(name: 'kick');
        // Give the user channel per-output data at the gateway; a user strip
        // must still not render per-output bars (design §6 — master-only).
        gateway.channels[kick.id]!.outputCount = 6;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MixSurface(engine: engine)),
          ),
        );
        await tickTelemetry(tester);

        final kickStrip = find.ancestor(
          of: find.text('kick'),
          matching: find.byType(ChannelStrip),
        );
        expect(
          find.descendant(
            of: kickStrip,
            matching: find.byKey(ChannelStrip.outputMeterKey(0)),
          ),
          findsNothing,
        );
      });
    });

    // ── Return delete-impact (design §4, §7) ─────────────────────────────────

    testWidgets('deleting a return with a sender warns before removing', (
      tester,
    ) async {
      final kick = engine.addChannel(name: 'kick');
      final verb = engine.addReturn(name: 'verb');
      engine.setChannelSend(kick, 0, returnBus: verb, level: 0.5);
      await pumpSurface(tester);
      expect(engine.channelSends(kick), hasLength(1));

      await tester.tap(find.byKey(MixSurface.returnRemoveKey('verb')));
      await tester.pumpAndSettle();

      // The delete-impact dialog warns, listing the stranded sender.
      expect(find.byType(DeleteImpactDialog), findsOneWidget);
      expect(find.textContaining('mix.kick'), findsOneWidget);
      // Nothing removed yet — the delete waits on confirmation.
      expect(engine.returns.value, hasLength(1));
      expect(engine.channelSends(kick), hasLength(1));

      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();

      // Confirmed: the return is gone and the sender's send was cleared.
      expect(engine.returns.value, isEmpty);
      expect(engine.channelSends(kick), isEmpty);
    });

    testWidgets('cancelling the delete-impact dialog keeps return and send', (
      tester,
    ) async {
      final kick = engine.addChannel(name: 'kick');
      final verb = engine.addReturn(name: 'verb');
      engine.setChannelSend(kick, 0, returnBus: verb, level: 0.5);
      await pumpSurface(tester);

      await tester.tap(find.byKey(MixSurface.returnRemoveKey('verb')));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteImpactDialog), findsOneWidget);

      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();

      // Nothing changed — the return and its incoming send both survive.
      expect(engine.returns.value, hasLength(1));
      expect(engine.channelSends(kick), hasLength(1));
      expect(engine.channelSends(kick).single.to, mix(['verb']));
    });

    testWidgets(
      'deleting a return nobody sends to removes it without warning',
      (tester) async {
        engine.addReturn(name: 'verb');
        await pumpSurface(tester);
        expect(engine.returns.value, hasLength(1));

        await tester.tap(find.byKey(MixSurface.returnRemoveKey('verb')));
        await tester.pumpAndSettle();

        // No senders → no warning, removed outright.
        expect(find.byType(DeleteImpactDialog), findsNothing);
        expect(engine.returns.value, isEmpty);
      },
    );
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
