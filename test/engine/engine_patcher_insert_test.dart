import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/mixer_channel.dart';

import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_patcher_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// A patcher as an **insert effect** — the `fx.` kind `patcherInsert` wrapping a
/// `patch.` reference, placed through the mix INSERTS area (design
/// `docs/design/patcher.md` §4 role 2, issue #225). Drives the engine seam
/// through the fakes: creating the wrapper, materialising it into a bus's insert
/// chain (borrowing the same live native patcher the editor edits, so edits are
/// heard live), delete-impact both directions, and reorder / move.
void main() {
  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);
  EntityAddress patch(String name) =>
      EntityAddress(kind: RegistryKinds.patch, segments: [name]);

  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late FakePatcherGateway patchers;
  late PhiEngine engine;
  late List<ProjectCommand> recorded;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    patchers = FakePatcherGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: synths,
      fxGateway: fxs,
      patcherGateway: patchers,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    recorded = [];
  });

  tearDown(() async {
    await engine.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  /// Binds a registry with two buses (`mix.drums`, `mix.bass`), a `patch.swirl`,
  /// and a plain `fx.crush`, ready for the insert flows.
  ProjectRegistry bind() {
    final registry = ProjectRegistry();
    registry.createEntity(
      mix('drums'),
      payload: const MixStrip(voice: 1).toJson(),
    );
    registry.createEntity(
      mix('bass'),
      payload: const MixStrip(voice: 2).toJson(),
    );
    registry.createEntity(patch('swirl'), payload: PatchPayload.empty.toJson());
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

  FakeMaterialisedFx wrapperHandle() =>
      fxs.handles.lastWhere((h) => h.kind == FxKind.patcherInsert);

  group('creation + placement', () {
    test('a patch is offered until it has a wrapper, then flows as fx', () {
      final registry = bind();
      final drums = channel('drums');

      // Before placement: offered as a patcher insert, not as a plain fx.
      expect(engine.availablePatchesToInsert(drums), [patch('swirl')]);
      expect(engine.availableFxFor(drums), [fx('crush')]);

      engine.addPatchInsert(drums, patch('swirl'));

      // The wrapper fx entity now exists (named after the patch) and is placed.
      expect(engine.channelInserts(drums), [fx('swirl')]);
      expect(engine.fxKindOf(fx('swirl')), FxKind.patcherInsert);
      // No longer offered as a patch — its wrapper flows through the fx picker
      // like any other insert.
      expect(engine.availablePatchesToInsert(drums), isEmpty);
      // The wrapper referenced the patch and the placement journalled commands.
      expect(registry.referencesOf(fx('swirl')), {patch('swirl')});
      expect(recorded, isNotEmpty);
    });

    test('materialises the wrapper into the bus chain, borrowing the patcher', () {
      bind();
      final drums = channel('drums');

      engine.addPatchInsert(drums, patch('swirl'));

      // The chain places the patcher-insert handle (placeable — a live patcher
      // was resolved), in order.
      expect(fxs.chains, hasLength(1));
      expect(fxs.chains.single.walkFromHead().map((h) => h.kind.name), [
        'patcherInsert',
      ]);
      // It borrows the *same* live native instance the editor edits, so edits to
      // the patch are heard live through the insert.
      expect(
        wrapperHandle().patchInstanceId,
        engine.patches.instanceIdOf(patch('swirl')),
      );
      expect(wrapperHandle().patchInstanceId, isNotNull);
    });

    test('a plain insert and a patcher insert coexist in order', () {
      bind();
      final drums = channel('drums');

      engine.addChannelInsert(drums, fx('crush'));
      engine.addPatchInsert(drums, patch('swirl'));

      expect(engine.channelInserts(drums), [fx('crush'), fx('swirl')]);
      expect(fxs.chains.single.walkFromHead().map((h) => h.kind.name), [
        'compressor',
        'patcherInsert',
      ]);
    });
  });

  group('delete-impact both directions', () {
    test('deleting the patch lists its insert wrapper', () {
      final registry = bind();
      engine.addPatchInsert(channel('drums'), patch('swirl'));

      final impact = registry.impactOfRemoving(patch('swirl'));

      expect(impact.hasReferrers, isTrue);
      expect(impact.referrers, contains(fx('swirl')));
    });

    test('deleting the wrapper fx lists the bus that inserts it', () {
      final registry = bind();
      engine.addPatchInsert(channel('drums'), patch('swirl'));

      final impact = registry.impactOfRemoving(fx('swirl'));

      expect(impact.referrers, contains(mix('drums')));
    });

    test('removing the wrapped patch drops the insert from the chain', () {
      final registry = bind();
      final drums = channel('drums');
      engine.addPatchInsert(drums, patch('swirl'));
      final handle = wrapperHandle();
      expect(fxs.chains.single.walkFromHead(), isNotEmpty);

      // Delete the patch — its native instance is freed only after the chain has
      // dropped the now-unplaceable wrapper (no freed patcher stays linked).
      registry.remove(patch('swirl'));

      expect(engine.patches.isOpen(patch('swirl')), isFalse);
      expect(handle.isDisposed, isTrue);
      expect(fxs.chains.single.walkFromHead(), isEmpty);
    });
  });

  group('reorder / move (like any other insert)', () {
    test('reorder places a patcher insert ahead of a plain one', () {
      bind();
      final drums = channel('drums');
      engine.addChannelInsert(drums, fx('crush'));
      engine.addPatchInsert(drums, patch('swirl'));
      expect(engine.channelInserts(drums), [fx('crush'), fx('swirl')]);

      engine.moveChannelInsertBefore(drums, fx('swirl'), fx('crush'));

      expect(engine.channelInserts(drums), [fx('swirl'), fx('crush')]);
      expect(fxs.chains.single.walkFromHead().map((h) => h.kind.name), [
        'patcherInsert',
        'compressor',
      ]);
    });

    test('placing the wrapper on another bus moves it (one-bus invariant)', () {
      bind();
      final drums = channel('drums');
      final bass = channel('bass');
      engine.addPatchInsert(drums, patch('swirl'));
      expect(engine.busHoldingInsert(fx('swirl')), mix('drums'));

      // The wrapper is a normal fx now — the bass picker offers it (not the
      // patch), and choosing it moves it off drums.
      expect(engine.availablePatchesToInsert(bass), isEmpty);
      expect(engine.availableFxFor(bass), contains(fx('swirl')));
      engine.addChannelInsert(bass, fx('swirl'));

      expect(engine.channelInserts(drums), isEmpty);
      expect(engine.channelInserts(bass), [fx('swirl')]);
    });
  });
}
