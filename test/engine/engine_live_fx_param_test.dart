import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/bridge/bus_tap.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_bus_tap.dart';
import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// The control plane's **fx leg** in production (issue #348): a
/// `phi.ctl.fx.<addr>.<param>` frame through the engine's own dispatcher moves
/// the live effect handle's param — unjournaled, the authored definition
/// untouched — and survives an unrelated re-sync, while a journaled edit of the
/// effect re-applies over it.
void main() {
  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  late FakeYseGateway yse;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late FakeBusTap busTap;
  late PhiEngine engine;
  late List<ProjectCommand> recorded;

  setUp(() {
    yse = FakeYseGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    busTap = FakeBusTap();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: FakeSynthGateway(),
      fxGateway: fxs,
      busTap: busTap,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    recorded = [];
  });

  tearDown(() async {
    await engine.dispose();
    await busTap.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  const reverbDef = FxDefinition(
    kind: FxKind.lowpassDelay,
    params: {'impact': 0.8, 'frequency': 1200},
  );

  /// Binds a registry with `mix.drums` carrying an `fx.reverb` insert.
  ProjectRegistry bind() {
    final registry = ProjectRegistry();
    registry.createEntity(fx('reverb'), payload: reverbDef.toJson());
    registry.createEntity(
      mix('drums'),
      payload: MixStrip(voice: 1, inserts: [fx('reverb')]).toJson(),
    );
    addTearDown(registry.dispose);
    engine.start();
    engine.bindProject(registry, recordCommand: recorded.add);
    return registry;
  }

  FakeMaterialisedFx reverb() =>
      fxs.handles.lastWhere((h) => h.kind == FxKind.lowpassDelay);

  Future<void> publish(String topic, BusValue value) async {
    busTap.publish(topic, value);
    await pumpEventQueue();
  }

  test('a phi.ctl.fx set moves the live handle param, unjournaled', () async {
    final registry = bind();
    final handle = reverb();

    await publish('phi.ctl.fx.reverb.impact', const BusFloat(0.25));

    expect(handle.liveParams, {'impact': 0.25});
    expect(handle.calls.last, 'set:impact=0.25');
    // Performance, not authorship: the definition and the registry payload are
    // untouched and nothing was journaled.
    expect(handle.definition, reverbDef);
    expect(
      FxDefinition.fromJson(
        (registry.entityAt(fx('reverb'))!.payload as Map)
            .cast<String, Object?>(),
      ),
      reverbDef,
    );
    expect(recorded, isEmpty);
    expect(engine.lastStateNotice.value, isNull);
  });

  test('an unrelated re-sync keeps the live value; a journaled edit of the '
      'effect re-applies over it', () async {
    final registry = bind();
    final handle = reverb();

    await publish('phi.ctl.fx.reverb.impact', const BusFloat(0.25));
    final applied = handle.liveApplyCount;

    // An unrelated registry change re-syncs the racks — the handle's definition
    // still equals the registry's, so nothing re-applies over the live value.
    registry.createEntity(
      mix('bass'),
      payload: const MixStrip(voice: 2).toJson(),
    );
    expect(handle.liveApplyCount, applied);
    expect(handle.liveParams, {'impact': 0.25});

    // A journaled edit of the effect's definition is authorship: it re-applies.
    final edited = reverbDef.withParam('impact', 0.5);
    registry.updateEntityPayload(fx('reverb'), edited.toJson());
    expect(handle.liveApplyCount, applied + 1);
    expect(handle.definition, edited);
  });

  test('an fx address with no live effect is a graceful no-op', () async {
    bind();
    final handle = reverb();

    await publish('phi.ctl.fx.nowhere.impact', const BusFloat(0.4));

    expect(handle.liveParams, isEmpty);
    expect(engine.lastStateNotice.value, isNull);
  });

  test('a set after stop reaches nothing', () async {
    bind();
    final handle = reverb();
    engine.stop();

    await publish('phi.ctl.fx.reverb.impact', const BusFloat(0.4));

    expect(handle.liveParams, isEmpty);
  });
}
