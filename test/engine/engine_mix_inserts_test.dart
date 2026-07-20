import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/mixer_channel.dart';

import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// The Mix INSERTS façade on [PhiEngine] (issue #212, racks design §5): a bus's
/// ordered `fx.` chain — [PhiEngine.channelInserts] / [availableFxFor] /
/// [addChannelInsert] (append + move-with-impact) / [removeChannelInsert] /
/// [moveChannelInsertBefore] / [busHoldingInsert] / [fxKindOf]. Every structural
/// edit is a journaled `mix.` payload command; the fx materialisation itself is
/// covered by `engine_racks_test`, so this drives the placement seam through the
/// fakes.
void main() {
  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late PhiEngine engine;
  late List<ProjectCommand> recorded;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    engine = PhiEngine(
      yse,
      synthGateway: synths,
      fxGateway: fxs,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    recorded = [];
  });

  tearDown(() async {
    await engine.dispose();
    await yse.dispose();
  });

  /// Binds a registry carrying two strips (`mix.drums`, `mix.bass`) and two fx
  /// instances (`fx.big_delay` = lowpassDelay, `fx.crush` = compressor), so the
  /// insert API has real buses and effects to move between.
  ProjectRegistry bindWithFx() {
    final registry = ProjectRegistry();
    registry.createEntity(
      mix('drums'),
      payload: const MixStrip(voice: 1).toJson(),
    );
    registry.createEntity(
      mix('bass'),
      payload: const MixStrip(voice: 2).toJson(),
    );
    registry.createEntity(
      fx('big_delay'),
      payload: const FxDefinition(kind: FxKind.lowpassDelay).toJson(),
    );
    registry.createEntity(
      fx('crush'),
      payload: const FxDefinition(kind: FxKind.compressor).toJson(),
    );
    addTearDown(registry.dispose);
    engine.start();
    engine.bindProject(registry, recordCommand: recorded.add);
    return registry;
  }

  MixerChannel channel(String name) =>
      engine.channels.value.firstWhere((c) => c.name == name);

  group('read surface', () {
    test('channelInserts is empty and availableFxFor lists every fx', () {
      bindWithFx();
      final drums = channel('drums');

      expect(engine.channelInserts(drums), isEmpty);
      expect(engine.availableFxFor(drums), [fx('big_delay'), fx('crush')]);
      expect(engine.busHoldingInsert(fx('big_delay')), isNull);
    });

    test('fxKindOf decodes the fx kind, null off an fx', () {
      bindWithFx();
      expect(engine.fxKindOf(fx('big_delay')), FxKind.lowpassDelay);
      expect(engine.fxKindOf(fx('crush')), FxKind.compressor);
      expect(engine.fxKindOf(fx('nope')), isNull);
    });
  });

  group('add / remove', () {
    test('addChannelInsert appends to the chain and journals a command', () {
      bindWithFx();
      final drums = channel('drums');

      engine.addChannelInsert(drums, fx('big_delay'));
      engine.addChannelInsert(drums, fx('crush'));

      expect(engine.channelInserts(drums), [fx('big_delay'), fx('crush')]);
      // Once placed, the fx is no longer offered on this bus.
      expect(engine.availableFxFor(drums), isEmpty);
      expect(engine.busHoldingInsert(fx('big_delay')), mix('drums'));
      expect(recorded, hasLength(2));
    });

    test('addChannelInsert is a no-op for an fx already on this bus', () {
      bindWithFx();
      final drums = channel('drums');
      engine.addChannelInsert(drums, fx('big_delay'));
      recorded.clear();

      engine.addChannelInsert(drums, fx('big_delay'));

      expect(engine.channelInserts(drums), [fx('big_delay')]);
      expect(recorded, isEmpty);
    });

    test('removeChannelInsert detaches the placement, fx stays available', () {
      bindWithFx();
      final drums = channel('drums');
      engine.addChannelInsert(drums, fx('big_delay'));
      engine.addChannelInsert(drums, fx('crush'));

      engine.removeChannelInsert(drums, 0);

      expect(engine.channelInserts(drums), [fx('crush')]);
      // The removed fx is offered again (its entity survives).
      expect(engine.availableFxFor(drums), [fx('big_delay')]);
      expect(engine.busHoldingInsert(fx('big_delay')), isNull);
    });

    test('removeChannelInsert ignores an out-of-range slot', () {
      bindWithFx();
      final drums = channel('drums');
      engine.addChannelInsert(drums, fx('big_delay'));
      recorded.clear();

      engine.removeChannelInsert(drums, 5);

      expect(engine.channelInserts(drums), [fx('big_delay')]);
      expect(recorded, isEmpty);
    });
  });

  group('move with impact (one bus at most)', () {
    test('placing an fx on another bus moves it off the first', () {
      bindWithFx();
      final drums = channel('drums');
      final bass = channel('bass');
      engine.addChannelInsert(drums, fx('big_delay'));
      expect(engine.busHoldingInsert(fx('big_delay')), mix('drums'));

      // The surface confirms via the impact dialog first; the engine performs
      // the move — removed from drums, appended to bass.
      engine.addChannelInsert(bass, fx('big_delay'));

      expect(engine.channelInserts(drums), isEmpty);
      expect(engine.channelInserts(bass), [fx('big_delay')]);
      expect(engine.busHoldingInsert(fx('big_delay')), mix('bass'));
    });
  });

  group('reorder', () {
    test('moveChannelInsertBefore reorders within the chain', () {
      bindWithFx();
      final drums = channel('drums');
      engine.addChannelInsert(drums, fx('big_delay'));
      engine.addChannelInsert(drums, fx('crush'));
      expect(engine.channelInserts(drums), [fx('big_delay'), fx('crush')]);

      // Drop crush before big_delay → crush leads.
      engine.moveChannelInsertBefore(drums, fx('crush'), fx('big_delay'));

      expect(engine.channelInserts(drums), [fx('crush'), fx('big_delay')]);
    });

    test(
      'moveChannelInsertBefore an absent anchor sends the fx to the tail',
      () {
        bindWithFx();
        final drums = channel('drums');
        engine.addChannelInsert(drums, fx('big_delay'));
        engine.addChannelInsert(drums, fx('crush'));

        // `bass` is not in the chain → big_delay goes to the end.
        engine.moveChannelInsertBefore(drums, fx('big_delay'), fx('bass'));

        expect(engine.channelInserts(drums), [fx('crush'), fx('big_delay')]);
      },
    );
  });
}
