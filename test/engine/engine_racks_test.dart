import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/mix/mix_strip.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/engine/engine.dart';

import 'test_doubles/fake_fx_gateway.dart';
import 'test_doubles/fake_midi_gateway.dart';
import 'test_doubles/fake_synth_gateway.dart';
import 'test_doubles/fake_yse_gateway.dart';

/// Engine-side voice + fx materialisation and session transport wiring (issue
/// #208, design `docs/design/racks-and-voices.md` §3, §5, §6). `PhiEngine`
/// reconciles the `voice.` / `synth.` / `fx.` registry the way it reconciles
/// `mix.` channels: it materialises one engine synth per internal voice (bound
/// to its bus), re-applies definition edits to every dependent voice, links each
/// bus's `inserts` into a placed chain, and — through the MIDI controller —
/// connects each playing session's transport to the synths / MIDI-out its clip
/// routes to. Exercised entirely through the fakes.
void main() {
  EntityAddress voice(String name) =>
      EntityAddress(kind: RegistryKinds.voice, segments: [name]);
  EntityAddress synth(String name) =>
      EntityAddress(kind: RegistryKinds.synth, segments: [name]);
  EntityAddress fx(String name) =>
      EntityAddress(kind: RegistryKinds.fx, segments: [name]);
  EntityAddress mix(String name) =>
      EntityAddress(kind: RegistryKinds.mix, segments: [name]);

  final master = mix('master');

  late FakeYseGateway yse;
  late FakeSynthGateway synths;
  late FakeFxGateway fxs;
  late FakeMidiGateway midi;
  late PhiEngine engine;

  setUp(() {
    yse = FakeYseGateway();
    synths = FakeSynthGateway();
    fxs = FakeFxGateway();
    midi = FakeMidiGateway();
    engine = PhiEngine(
      yse,
      midiGateway: midi,
      synthGateway: synths,
      fxGateway: fxs,
      telemetryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await midi.dispose();
    await yse.dispose();
  });

  /// A registry with [synths]/[voices]/[buses]/[fx] built, ready to bind.
  ProjectRegistry buildRegistry({Map<EntityAddress, Object>? entities}) {
    final registry = ProjectRegistry();
    entities?.forEach((address, payload) {
      final map = payload is MixStrip
          ? payload.toJson()
          : payload is VoiceDefinition
          ? payload.toJson()
          : payload is FmSynth
          ? payload.toJson()
          : payload is SineSynth
          ? payload.toJson()
          : payload is FxDefinition
          ? payload.toJson()
          : payload;
      registry.createEntity(address, payload: map);
    });
    return registry;
  }

  group('voice → synth materialisation', () {
    test('materialises one synth per internal voice on its channel + bus', () {
      final registry = buildRegistry(
        entities: {
          synth('sine'): const SineSynth(),
          mix('drums'): const MixStrip(voice: 1),
          voice('default'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: master,
          ),
          voice('lead'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: mix('drums'),
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      // Two voices sharing one definition → two distinct engine synths.
      expect(synths.synths, hasLength(2));
      // Stable channels 1 + 2 (0-based 0 + 1 through the resolver).
      expect(engine.midi.voiceResolver.channelFor('voice.default'), 0);
      expect(engine.midi.voiceResolver.channelFor('voice.lead'), 1);
      // The default voice binds to master (null bus); the lead binds to drums.
      final drumsId = engine.channels.value
          .firstWhere((c) => c.name == 'drums')
          .id;
      final defaultSynth = engine.midi.synthForVoice('voice.default')!;
      final leadSynth = engine.midi.synthForVoice('voice.lead')!;
      expect(defaultSynth.boundBus, isNull);
      expect(leadSynth.boundBus, drumsId);
      expect((defaultSynth as FakeMaterialisedSynth).channel, 1);
      expect((leadSynth as FakeMaterialisedSynth).channel, 2);
    });

    test('a live definition edit re-applies to every dependent voice', () {
      const bank = 'assets/bells.syx';
      final registry = buildRegistry(
        entities: {
          synth('bells'): const FmSynth(bankAsset: bank, patchIndex: 4),
          voice('a'): VoiceDefinition.internal(
            synth: synth('bells'),
            output: master,
          ),
          voice('b'): VoiceDefinition.internal(
            synth: synth('bells'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      expect(synths.synths, hasLength(2));

      // A patch tweak within the same bank is a live setter — no rebuild.
      registry.updateEntityPayload(
        synth('bells'),
        const FmSynth(bankAsset: bank, patchIndex: 7).toJson(),
      );

      // Both dependent voices re-applied in place (same handles, no rebuild).
      expect(synths.synths, hasLength(2));
      for (final s in synths.synths) {
        expect(s.liveApplyCount, 1);
        expect(s.materialiseCount, 1);
        expect(s.isDisposed, isFalse);
      }
    });

    test('a rebuild-forcing edit mints a fresh synth, disposing the old', () {
      final registry = buildRegistry(
        entities: {
          synth('bells'): const FmSynth(bankAsset: 'a.syx', patchIndex: 0),
          voice('a'): VoiceDefinition.internal(
            synth: synth('bells'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final original = engine.midi.synthForVoice('voice.a')!;

      // A bank swap can't be a live setter — the voice pool rebuilds.
      registry.updateEntityPayload(
        synth('bells'),
        const FmSynth(bankAsset: 'b.syx', patchIndex: 0).toJson(),
      );

      final rebuilt = engine.midi.synthForVoice('voice.a')!;
      expect(identical(rebuilt, original), isFalse);
      expect((original as FakeMaterialisedSynth).isDisposed, isTrue);
      expect((rebuilt as FakeMaterialisedSynth).isDisposed, isFalse);
    });

    test('re-pointing a voice bus re-binds the same synth', () {
      final registry = buildRegistry(
        entities: {
          synth('sine'): const SineSynth(),
          mix('drums'): const MixStrip(voice: 1),
          voice('a'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final handle =
          engine.midi.synthForVoice('voice.a')! as FakeMaterialisedSynth;
      expect(handle.boundBus, isNull);
      final bindsBefore = handle.bindCount;

      registry.updateEntityPayload(
        voice('a'),
        VoiceDefinition.internal(
          synth: synth('sine'),
          output: mix('drums'),
        ).toJson(),
      );

      final drumsId = engine.channels.value
          .firstWhere((c) => c.name == 'drums')
          .id;
      // Same handle, re-bound to the new bus (no rebuild).
      expect(identical(engine.midi.synthForVoice('voice.a'), handle), isTrue);
      expect(handle.boundBus, drumsId);
      expect(handle.bindCount, greaterThan(bindsBefore));
      expect(handle.materialiseCount, 1);
    });

    test('re-pointing a voice synth swaps the engine synth', () {
      final registry = buildRegistry(
        entities: {
          synth('sine'): const SineSynth(),
          synth('bells'): const FmSynth(bankAsset: 'a.syx', patchIndex: 0),
          voice('a'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final before = engine.midi.synthForVoice('voice.a')!;
      expect(before.kind.name, 'sine');

      registry.updateEntityPayload(
        voice('a'),
        VoiceDefinition.internal(
          synth: synth('bells'),
          output: master,
        ).toJson(),
      );

      final after = engine.midi.synthForVoice('voice.a')!;
      expect(after.kind.name, 'fm');
      expect((before as FakeMaterialisedSynth).isDisposed, isTrue);
      expect((after as FakeMaterialisedSynth).isDisposed, isFalse);
    });

    test('deleting a voice disposes its synth and frees its channel', () {
      final registry = buildRegistry(
        entities: {
          synth('sine'): const SineSynth(),
          voice('a'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final handle =
          engine.midi.synthForVoice('voice.a')! as FakeMaterialisedSynth;

      registry.remove(voice('a'));

      expect(handle.isDisposed, isTrue);
      expect(engine.midi.synthForVoice('voice.a'), isNull);
      expect(engine.midi.voiceResolver.channelFor('voice.a'), isNull);
    });
  });

  group('external voices', () {
    test('carry a MIDI channel and materialise no synth', () {
      final registry = buildRegistry(
        entities: {
          voice('hw'): VoiceDefinition.external(channel: 5, output: master),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      expect(synths.synths, isEmpty);
      expect(engine.midi.isExternalVoice('voice.hw'), isTrue);
      // External channel 5 → 0-based 4.
      expect(engine.midi.voiceResolver.channelFor('voice.hw'), 4);
    });
  });

  group('fx insert chains', () {
    ProjectRegistry busWithInserts(List<EntityAddress> inserts) =>
        buildRegistry(
          entities: {
            fx('a'): const FxDefinition(kind: FxKind.lowpass, params: {}),
            fx('b'): const FxDefinition(kind: FxKind.phaser, params: {}),
            mix('drums'): MixStrip(voice: 1, inserts: inserts),
          },
        );

    test('materialises a placed chain from a bus inserts list, in order', () {
      final registry = busWithInserts([fx('a'), fx('b')]);
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      expect(fxs.handles, hasLength(2));
      expect(fxs.chains, hasLength(1));
      final chain = fxs.chains.single;
      final drumsId = engine.channels.value
          .firstWhere((c) => c.name == 'drums')
          .id;
      expect(chain.busChannelId, drumsId);
      expect(chain.attached, isTrue);
      // Head-to-tail order matches the inserts list, and the walk terminates.
      expect(chain.walkFromHead().map((h) => h.kind.name), [
        'lowpass',
        'phaser',
      ]);
    });

    test('reordering the inserts re-places the chain', () {
      final registry = busWithInserts([fx('a'), fx('b')]);
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      registry.updateEntityPayload(
        mix('drums'),
        MixStrip(voice: 1, inserts: [fx('b'), fx('a')]).toJson(),
      );

      expect(fxs.chains.single.walkFromHead().map((h) => h.kind.name), [
        'phaser',
        'lowpass',
      ]);
    });

    test('emptying the inserts detaches and disposes the chain', () {
      final registry = busWithInserts([fx('a'), fx('b')]);
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final chain = fxs.chains.single;

      registry.updateEntityPayload(
        mix('drums'),
        const MixStrip(voice: 1).toJson(),
      );

      expect(chain.isDisposed, isTrue);
      expect(chain.attached, isFalse);
    });

    test('deleting an fx instance disposes its handle', () {
      final registry = busWithInserts([fx('a'), fx('b')]);
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      final handleB = fxs.handles.firstWhere((h) => h.kind == FxKind.phaser);

      // The bus drops fx.b first (so the chain releases the borrowed handle),
      // then the instance is deleted.
      registry.updateEntityPayload(
        mix('drums'),
        MixStrip(voice: 1, inserts: [fx('a')]).toJson(),
      );
      registry.remove(fx('b'));

      expect(handleB.isDisposed, isTrue);
      expect(fxs.chains.single.walkFromHead().map((h) => h.kind.name), [
        'lowpass',
      ]);
    });
  });

  group('session transports connect by routed voice', () {
    test('playing connects the routed internal synth, not MIDI-out', () {
      // No clip entity: the boot session keeps the default demo chain, which
      // routes to voice.default.
      final registry = buildRegistry(
        entities: {
          synth('sine'): const SineSynth(),
          voice('default'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);

      engine.midi.play();
      addTearDown(engine.midi.stop);

      final handle = engine.midi.synthForVoice('voice.default');
      final transport = midi.transport!;
      expect(transport.connectedSynths, [handle]);
      expect(transport.midiOutConnected, isFalse);
    });

    test('a clip routed to a deleted voice degrades gracefully', () {
      final registry = buildRegistry(
        entities: {
          synth('sine'): const SineSynth(),
          voice('default'): VoiceDefinition.internal(
            synth: synth('sine'),
            output: master,
          ),
        },
      );
      addTearDown(registry.dispose);

      engine.start();
      engine.bindProject(registry);
      engine.midi.play();
      addTearDown(engine.midi.stop);

      // Delete the voice every note routes to while it plays.
      registry.remove(voice('default'));

      // The unknown voice is surfaced, its synth is gone, and nothing crashed.
      expect(engine.midi.unresolvedVoices, contains('voice.default'));
      expect(engine.midi.synthForVoice('voice.default'), isNull);
      expect(midi.transport!.connectedSynths, isEmpty);
    });
  });
}
