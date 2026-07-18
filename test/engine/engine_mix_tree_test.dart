import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_send.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/mixer_channel.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// Tree-aware reconciliation in `PhiEngine` (issue #168, design §5, §8): the
/// engine materialises a channel per `mix.` node (groups before their children,
/// returns outside the tree), re-parents a moved node with `moveChannel`, wires
/// aux sends in a second pass once every channel exists, and collapses the
/// tree-wide solo/mute state into effective gateway volumes.
void main() {
  EntityAddress mix(List<String> segments) =>
      EntityAddress(kind: RegistryKinds.mix, segments: segments);

  late FakeYseGateway gateway;
  late PhiEngine engine;

  setUp(() {
    gateway = FakeYseGateway();
    engine = PhiEngine(
      gateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await gateway.dispose();
  });

  /// The materialised non-return channel named [name] (its address leaf).
  MixerChannel channel(String name) =>
      engine.channels.value.firstWhere((c) => c.name == name);

  /// The gateway id of the (return) channel named [name].
  int gatewayId(String name) =>
      gateway.channels.entries.firstWhere((e) => e.value.name == name).key;

  double effective(String name) => gateway.channels[gatewayId(name)]!.volume;

  group('group create / reconciliation', () {
    test(
      'materialises a group bus before its children, parented correctly',
      () {
        final registry = ProjectRegistry()
          ..createGroup(
            mix(['drums']),
            payload: const MixStrip(voice: 2).toJson(),
          )
          ..createEntity(
            mix(['drums', 'kick']),
            payload: const MixStrip(voice: 1).toJson(),
          )
          ..createEntity(
            mix(['drums', 'snare']),
            payload: const MixStrip(voice: 3).toJson(),
          );
        addTearDown(registry.dispose);

        engine.start();
        engine.bindProject(registry);

        // Channels surface in tree pre-order: the group, then its children.
        expect(engine.channels.value.map((c) => c.name), [
          'drums',
          'kick',
          'snare',
        ]);
        // The group was created before its children (lower gateway id).
        final drumsId = gatewayId('drums');
        expect(gatewayId('kick'), greaterThan(drumsId));
        // The children parent to the group, not to master.
        expect(gateway.channels[gatewayId('kick')]!.parentId, drumsId);
        expect(gateway.channels[gatewayId('snare')]!.parentId, drumsId);
        // A top-level group parents to master.
        expect(gateway.channels[drumsId]!.parentId, isNull);
      },
    );
  });

  group('move (regroup) reconciliation', () {
    test('a reparented strip is moveChannel-d, not destroyed and rebuilt', () {
      final registry = ProjectRegistry()
        ..createGroup(
          mix(['drums']),
          payload: const MixStrip(voice: 2).toJson(),
        )
        ..createEntity(
          mix(['kick']),
          payload: const MixStrip(voice: 1).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final kickId = gatewayId('kick');
      final drumsId = gatewayId('drums');
      gateway.calls.clear();

      // Drag kick into the drums group — the address follows the tree.
      registry.move(mix(['kick']), mix(['drums', 'kick']));

      // The gateway channel was re-parented, keeping its id (identity + meters).
      expect(gateway.calls, contains('moveChannel:$kickId:$drumsId'));
      expect(
        gateway.calls.any((c) => c.startsWith('destroyChannel:$kickId')),
        isFalse,
      );
      expect(gateway.channels[kickId]!.parentId, drumsId);
      expect(engine.channels.value.map((c) => c.name), ['drums', 'kick']);
    });

    test('a reparent preserves the channel\'s live volume and mute', () {
      final registry = ProjectRegistry()
        ..createGroup(
          mix(['drums']),
          payload: const MixStrip(voice: 2).toJson(),
        )
        ..createEntity(
          mix(['kick']),
          payload: const MixStrip(voice: 1).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final kick = channel('kick');
      engine.setChannelVolume(kick, 0.33);
      engine.setChannelMuted(kick, muted: true);

      registry.move(mix(['kick']), mix(['drums', 'kick']));

      // Same MixerChannel instance survived the regroup.
      expect(identical(channel('kick'), kick), isTrue);
      expect(kick.volume, closeTo(0.33, 1e-9));
      expect(kick.muted, isTrue);
    });
  });

  group('remove reconciliation', () {
    test('removing a group destroys the whole subtree', () {
      final registry = ProjectRegistry()
        ..createGroup(
          mix(['drums']),
          payload: const MixStrip(voice: 2).toJson(),
        )
        ..createEntity(
          mix(['drums', 'kick']),
          payload: const MixStrip(voice: 1).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      expect(gateway.channels, hasLength(2));

      registry.remove(mix(['drums']));

      expect(engine.channels.value, isEmpty);
      expect(gateway.channels, isEmpty);
    });
  });

  group('returns', () {
    test(
      'a return entity is created outside the tree, excluded from channels',
      () {
        final registry = ProjectRegistry()
          ..createEntity(
            mix(['verb']),
            payload: const MixStrip(voice: 5, isReturn: true).toJson(),
          );
        addTearDown(registry.dispose);

        engine.start();
        engine.bindProject(registry);

        // Returns are not user strips — they get their own section later (#170).
        expect(engine.channels.value, isEmpty);
        // But a return channel exists at the gateway.
        expect(
          gateway.calls.any((c) => c.startsWith('createReturnChannel:')),
          isTrue,
        );
        expect(gateway.channels[gatewayId('verb')]!.isReturn, isTrue);
      },
    );

    test(
      'send slots auto-upgrade past four for a return with many senders',
      () {
        final registry = ProjectRegistry()
          ..createEntity(
            mix(['verb']),
            payload: MixStrip(
              voice: 5,
              isReturn: true,
              sends: [
                for (var i = 0; i < 6; i++) MixSend(to: mix(['verb'])),
              ],
            ).toJson(),
          );
        addTearDown(registry.dispose);

        engine.start();
        engine.bindProject(registry);

        expect(gateway.channels[gatewayId('verb')]!.sendSlots, 6);
      },
    );
  });

  group('second-pass send wiring', () {
    test('wires a send even when the sender precedes its return target', () {
      // The sender is created first (registry insertion order), so the target
      // does not yet exist during the first pass — only the second pass can
      // wire it (design §8, "targets must exist first").
      final registry = ProjectRegistry()
        ..createEntity(
          mix(['lead']),
          payload: MixStrip(
            voice: 1,
            sends: [
              MixSend(to: mix(['verb']), level: 0.4),
            ],
          ).toJson(),
        )
        ..createEntity(
          mix(['verb']),
          payload: const MixStrip(voice: 5, isReturn: true).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      final leadId = gatewayId('lead');
      final verbId = gatewayId('verb');
      expect(gateway.calls, contains('setSend:$leadId:0:$verbId:0.400:false'));
      final send = gateway.channels[leadId]!.sends[0]!;
      expect(send.returnId, verbId);
      expect(send.level, closeTo(0.4, 1e-9));
    });

    test('a send to a non-return target is skipped', () {
      final registry = ProjectRegistry()
        ..createEntity(mix(['pad']), payload: const MixStrip(voice: 2).toJson())
        ..createEntity(
          mix(['lead']),
          payload: MixStrip(
            voice: 1,
            sends: [
              MixSend(to: mix(['pad'])),
            ], // pad is a strip, not a return
          ).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      expect(gateway.channels[gatewayId('lead')]!.sends, isEmpty);
    });
  });

  group('solo / mute truth table over the tree', () {
    late ProjectRegistry registry;

    setUp(() {
      registry = ProjectRegistry()
        ..createGroup(
          mix(['drums']),
          payload: const MixStrip(voice: 2, volume: 0.9).toJson(),
        )
        ..createEntity(
          mix(['drums', 'kick']),
          payload: const MixStrip(voice: 1, volume: 0.8).toJson(),
        )
        ..createEntity(
          mix(['drums', 'snare']),
          payload: const MixStrip(voice: 3, volume: 0.7).toJson(),
        )
        ..createEntity(
          mix(['bass']),
          payload: const MixStrip(voice: 4, volume: 0.6).toJson(),
        )
        ..createEntity(
          mix(['verb']),
          payload: const MixStrip(
            voice: 5,
            volume: 0.5,
            isReturn: true,
          ).toJson(),
        );
      engine.start();
      engine.bindProject(registry);
    });

    tearDown(() => registry.dispose());

    test('with nothing muted or soloed every node plays at its own volume', () {
      expect(effective('drums'), closeTo(0.9, 1e-9));
      expect(effective('kick'), closeTo(0.8, 1e-9));
      expect(effective('snare'), closeTo(0.7, 1e-9));
      expect(effective('bass'), closeTo(0.6, 1e-9));
      expect(effective('verb'), closeTo(0.5, 1e-9));
    });

    test('muting a group silences its whole subtree', () {
      engine.setChannelMuted(channel('drums'), muted: true);

      expect(effective('drums'), 0.0);
      expect(effective('kick'), 0.0); // muted on the path
      expect(effective('snare'), 0.0);
      expect(effective('bass'), closeTo(0.6, 1e-9)); // untouched
      expect(effective('verb'), closeTo(0.5, 1e-9)); // returns unaffected
    });

    test('soloing a leaf keeps its ancestors open and silences the rest', () {
      engine.setChannelSoloed(channel('kick'), soloed: true);

      expect(effective('kick'), closeTo(0.8, 1e-9)); // the soloed node
      expect(effective('drums'), closeTo(0.9, 1e-9)); // ancestor stays open
      expect(effective('snare'), 0.0); // sibling silenced
      expect(effective('bass'), 0.0); // unrelated silenced
      expect(effective('verb'), closeTo(0.5, 1e-9)); // exempt from solo
    });

    test('soloing a group solos the whole family', () {
      engine.setChannelSoloed(channel('drums'), soloed: true);

      expect(effective('drums'), closeTo(0.9, 1e-9));
      expect(effective('kick'), closeTo(0.8, 1e-9)); // descendant audible
      expect(effective('snare'), closeTo(0.7, 1e-9));
      expect(effective('bass'), 0.0); // outside the family, silenced
    });

    test('a soloed leaf inside a muted group stays silent (mute wins)', () {
      engine.setChannelMuted(channel('drums'), muted: true);
      engine.setChannelSoloed(channel('kick'), soloed: true);

      expect(effective('kick'), 0.0); // mute on the path beats its own solo
      expect(effective('drums'), 0.0);
      expect(effective('snare'), 0.0);
      expect(effective('bass'), 0.0); // a solo is active, so it is silenced
      expect(effective('verb'), closeTo(0.5, 1e-9));
    });

    test('a muted return is silenced; solo never touches it', () {
      engine.setChannelSoloed(channel('bass'), soloed: true);
      expect(effective('verb'), closeTo(0.5, 1e-9)); // exempt from solo

      // Muting the return (returns are held channels too) silences it directly.
      final verb = engine.returns.value.single;
      engine.setChannelMuted(verb, muted: true);
      expect(effective('verb'), 0.0);
    });
  });

  group('send editing + gesture coalescing', () {
    late ProjectRegistry registry;
    late List<ProjectCommand> recorded;

    setUp(() {
      registry = ProjectRegistry()
        ..createEntity(
          mix(['lead']),
          payload: const MixStrip(voice: 1).toJson(),
        )
        ..createEntity(
          mix(['verb']),
          payload: const MixStrip(voice: 5, isReturn: true).toJson(),
        );
      recorded = <ProjectCommand>[];
      engine.start();
      engine.bindProject(registry, recordCommand: recorded.add);
    });

    tearDown(() => registry.dispose());

    MixerChannel returnBus() =>
        engine.returns.value.firstWhere((c) => c.name == 'verb');

    test('setChannelSend persists a send and wires the gateway', () {
      engine.setChannelSend(
        channel('lead'),
        0,
        returnBus: returnBus(),
        level: 0.5,
      );

      final leadId = gateway.channels.entries
          .firstWhere((e) => e.value.name == 'lead')
          .key;
      final verbId = gatewayId('verb');
      expect(gateway.channels[leadId]!.sends[0]!.returnId, verbId);
      expect(gateway.channels[leadId]!.sends[0]!.level, closeTo(0.5, 1e-9));
      // Persisted into the strip payload.
      final strip = MixStrip.fromJson(
        (registry.entityAt(mix(['lead']))!.payload! as Map).cast(),
      );
      expect(strip.sends.single.to, mix(['verb']));
    });

    test(
      'a send-level drag emits exactly one payload command, on gesture end',
      () {
        engine.setChannelSend(channel('lead'), 0, returnBus: returnBus());
        recorded.clear();

        engine.beginSendLevelGesture(channel('lead'), 0);
        engine.setChannelSendLevel(channel('lead'), 0, 0.2);
        engine.setChannelSendLevel(channel('lead'), 0, 0.35);

        // Mid-drag the gateway rams every tick …
        final leadId = gateway.channels.entries
            .firstWhere((e) => e.value.name == 'lead')
            .key;
        expect(gateway.channels[leadId]!.sends[0]!.level, closeTo(0.35, 1e-9));
        // … but nothing is journaled yet.
        expect(recorded, isEmpty);

        engine.endSendLevelGesture(channel('lead'), 0);

        // One command for the whole drag, carrying the final level.
        expect(recorded, hasLength(1));
        final strip = MixStrip.fromJson(
          (registry.entityAt(mix(['lead']))!.payload! as Map).cast(),
        );
        expect(strip.sends.single.level, closeTo(0.35, 1e-9));
      },
    );

    test('clearChannelSend detaches the send at the gateway and payload', () {
      engine.setChannelSend(channel('lead'), 0, returnBus: returnBus());
      final leadId = gateway.channels.entries
          .firstWhere((e) => e.value.name == 'lead')
          .key;
      expect(gateway.channels[leadId]!.sends, isNotEmpty);

      engine.clearChannelSend(channel('lead'), 0);

      expect(gateway.channels[leadId]!.sends, isEmpty);
      final strip = MixStrip.fromJson(
        (registry.entityAt(mix(['lead']))!.payload! as Map).cast(),
      );
      expect(strip.sends, isEmpty);
    });
  });
}
