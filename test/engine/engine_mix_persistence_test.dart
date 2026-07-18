import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/commands/update_entity_payload_command.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_yse_gateway.dart';

/// Live mix state (volume / mute / solo) persists through the `mix.` entity —
/// issue #136. The engine restores it when materialising a channel and, when the
/// performer changes it live, publishes it back via a **gesture-coalesced**
/// `UpdateEntityPayloadCommand` (one command per fader drag, one per toggle).
void main() {
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  MixStrip stripAt(ProjectRegistry registry, EntityAddress address) =>
      MixStrip.fromJson((registry.entityAt(address)!.payload! as Map).cast());

  Iterable<UpdateEntityPayloadCommand> payloadCommands(
    List<ProjectCommand> recorded,
  ) => recorded.whereType<UpdateEntityPayloadCommand>();

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

  group('restoring persisted state on materialisation', () {
    test('a materialised channel adopts its strip volume/mute/solo', () {
      final registry = ProjectRegistry()
        ..createEntity(
          mix('bass'),
          payload: const MixStrip(voice: 4, volume: 0.6).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      final ch = engine.channels.value.single;
      expect(ch.volume, closeTo(0.6, 1e-9));
      expect(ch.muted, isFalse);
      expect(ch.soloed, isFalse);
      // The effective gateway volume matches the restored fader value.
      expect(gateway.channels[ch.id]!.volume, closeTo(0.6, 1e-9));
    });

    test('a restored muted channel is silenced at the gateway', () {
      final registry = ProjectRegistry()
        ..createEntity(
          mix('pad'),
          payload: const MixStrip(voice: 1, volume: 0.8, muted: true).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      final ch = engine.channels.value.single;
      expect(ch.muted, isTrue);
      expect(ch.volume, closeTo(0.8, 1e-9)); // user volume preserved
      expect(gateway.channels[ch.id]!.volume, 0.0); // but silenced
    });

    test('a restored solo silences the other channels', () {
      final registry = ProjectRegistry()
        ..createEntity(
          mix('drum'),
          payload: const MixStrip(voice: 1, volume: 0.7, soloed: true).toJson(),
        )
        ..createEntity(
          mix('bass'),
          payload: const MixStrip(voice: 2, volume: 0.5).toJson(),
        );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      final drum = engine.channels.value[0];
      final bass = engine.channels.value[1];
      expect(drum.soloed, isTrue);
      expect(gateway.channels[drum.id]!.volume, closeTo(0.7, 1e-9));
      expect(gateway.channels[bass.id]!.volume, 0.0); // silenced by drum's solo
    });
  });

  group('gesture-coalesced volume persistence', () {
    late ProjectRegistry registry;
    late List<ProjectCommand> recorded;

    setUp(() {
      registry = ProjectRegistry();
      recorded = <ProjectCommand>[];
      engine.start();
      engine.bindProject(registry, recordCommand: recorded.add);
    });

    tearDown(() => registry.dispose());

    test('a fader drag emits exactly one payload command, on gesture end', () {
      final ch = engine.addChannel(name: 'drums');
      recorded.clear();

      engine.beginChannelVolumeGesture(ch);
      engine.setChannelVolume(ch, 0.1);
      engine.setChannelVolume(ch, 0.2);
      engine.setChannelVolume(ch, 0.3);

      // Mid-drag: the live channel + gateway track every tick …
      expect(ch.volume, closeTo(0.3, 1e-9));
      expect(gateway.channels[ch.id]!.volume, closeTo(0.3, 1e-9));
      // … but nothing is journaled and the registry payload is untouched.
      expect(payloadCommands(recorded), isEmpty);
      expect(stripAt(registry, mix('drums')).volume, 1.0);

      engine.endChannelVolumeGesture(ch);

      // One command for the whole drag, carrying only the final value.
      expect(payloadCommands(recorded), hasLength(1));
      expect(stripAt(registry, mix('drums')).volume, closeTo(0.3, 1e-9));
    });

    test('a volume set with no gesture persists immediately', () {
      final ch = engine.addChannel(name: 'drums');
      recorded.clear();

      engine.setChannelVolume(ch, 0.4);
      expect(payloadCommands(recorded), hasLength(1));
      expect(stripAt(registry, mix('drums')).volume, closeTo(0.4, 1e-9));

      engine.setChannelVolume(ch, 0.5);
      expect(payloadCommands(recorded), hasLength(2));
      expect(stripAt(registry, mix('drums')).volume, closeTo(0.5, 1e-9));
    });

    test('setting the already-persisted value records nothing (de-dupe)', () {
      final ch = engine.addChannel(name: 'drums');
      engine.setChannelVolume(ch, 0.4);
      recorded.clear();

      engine.setChannelVolume(ch, 0.4); // no change

      expect(payloadCommands(recorded), isEmpty);
    });

    test('the coalesced command is journal-encodable', () {
      final ch = engine.addChannel(name: 'drums');
      recorded.clear();
      engine.beginChannelVolumeGesture(ch);
      engine.setChannelVolume(ch, 0.25);
      engine.endChannelVolumeGesture(ch);

      final command = payloadCommands(recorded).single;
      final json = command.toJson();
      expect(json['type'], 'update_payload');
      expect(json['address'], 'mix.drums');
      expect((json['payload']! as Map)['volume'], closeTo(0.25, 1e-9));
    });

    test('beginning a new gesture flushes an unfinished previous one', () {
      final a = engine.addChannel(name: 'a');
      final b = engine.addChannel(name: 'b');
      recorded.clear();

      engine.beginChannelVolumeGesture(a);
      engine.setChannelVolume(a, 0.2);
      // No endChannelVolumeGesture(a) — a stray/interrupted gesture …
      engine.beginChannelVolumeGesture(b); // … is flushed here.

      expect(payloadCommands(recorded), hasLength(1));
      expect(stripAt(registry, mix('a')).volume, closeTo(0.2, 1e-9));

      engine.setChannelVolume(b, 0.9);
      engine.endChannelVolumeGesture(b);
      expect(stripAt(registry, mix('b')).volume, closeTo(0.9, 1e-9));
    });

    test('a master fader gesture persists nothing (no mix. entity)', () {
      recorded.clear();

      engine.beginChannelVolumeGesture(engine.masterChannel);
      engine.setChannelVolume(engine.masterChannel, 0.3);
      engine.endChannelVolumeGesture(engine.masterChannel);

      expect(payloadCommands(recorded), isEmpty);
      expect(engine.masterChannel.volume, closeTo(0.3, 1e-9));
    });
  });

  group('discrete mute / solo persistence', () {
    late ProjectRegistry registry;
    late List<ProjectCommand> recorded;

    setUp(() {
      registry = ProjectRegistry();
      recorded = <ProjectCommand>[];
      engine.start();
      engine.bindProject(registry, recordCommand: recorded.add);
    });

    tearDown(() => registry.dispose());

    test('muting persists one command carrying muted=true', () {
      final ch = engine.addChannel(name: 'drums');
      recorded.clear();

      engine.setChannelMuted(ch, muted: true);

      expect(payloadCommands(recorded), hasLength(1));
      expect(stripAt(registry, mix('drums')).muted, isTrue);
    });

    test('soloing persists only the toggled channel', () {
      final drum = engine.addChannel(name: 'drum');
      engine.addChannel(name: 'bass');
      recorded.clear();

      engine.setChannelSoloed(drum, soloed: true);

      // drum's own soloed flag is persisted …
      expect(stripAt(registry, mix('drum')).soloed, isTrue);
      // … but bass is silenced only in *effective* volume, not persisted state.
      expect(stripAt(registry, mix('bass')).soloed, isFalse);
      expect(payloadCommands(recorded), hasLength(1));
    });
  });
}
