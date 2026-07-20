import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/fx/fx_definition.dart';
import 'package:phi/domain/fx/fx_kind.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/synth/fm_synth.dart';
import 'package:phi/domain/synth/sampler_synth.dart';
import 'package:phi/domain/synth/sine_synth.dart';
import 'package:phi/domain/synth/synth_kind.dart';
import 'package:phi/domain/synth/va_synth.dart';
import 'package:phi/domain/voice/voice_definition.dart';
import 'package:phi/domain/voice/voice_kind.dart';
import 'package:phi/engine/state/rack_definitions_controller.dart';

EntityAddress _addr(String dotted) => EntityAddress.parse(dotted);

void main() {
  group('RackDefinitionsController', () {
    late ProjectRegistry registry;
    late List<ProjectCommand> recorded;
    late RackDefinitionsController controller;

    setUp(() {
      registry = ProjectRegistry();
      recorded = [];
      controller = RackDefinitionsController(
        registry: registry,
        recordCommand: recorded.add,
      );
    });

    tearDown(() {
      controller.dispose();
      registry.dispose();
    });

    void seed() {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      registry.createEntity(
        _addr('synth.keys.piano'),
        payload: const SineSynth().toJson(),
      );
      registry.createEntity(_addr('fx.reverb'), payload: {'kind': 'lowpass'});
    }

    test(
      'renders the synth./fx. namespaces as ordered trees with kind tags',
      () {
        seed();

        final synths = controller.synthTree;
        expect(synths.map((n) => n.name), ['lead', 'keys']);
        expect(synths.first.isGroup, isFalse);
        expect(synths.first.kindTag, 'va');

        final keys = synths[1];
        expect(keys.isGroup, isTrue);
        expect(keys.children.single.name, 'piano');
        expect(keys.children.single.kindTag, 'sine');

        final fx = controller.fxTree;
        expect(fx.single.name, 'reverb');
        expect(fx.single.kindTag, 'lowpass');
      },
    );

    test('notifies when the registry mutates', () {
      var notifications = 0;
      controller.addListener(() => notifications++);

      registry.createEntity(
        _addr('synth.lead'),
        payload: const SineSynth().toJson(),
      );

      expect(notifications, greaterThan(0));
      expect(controller.synthTree, hasLength(1));
    });

    test(
      'newSynth creates, records, selects with the kind default payload',
      () {
        for (final kind in SynthKind.values) {
          recorded.clear();
          final address = controller.newSynth(kind);
          expect(registry.entityAt(address), isNotNull);
          expect(controller.selected, address);
          expect(controller.kindTagAt(address), kind.name);
          expect(recorded, hasLength(1));
        }
        // Distinct default addresses per kind.
        expect(registry.contains(_addr('synth.sine')), isTrue);
        expect(registry.contains(_addr('synth.va')), isTrue);
        expect(registry.contains(_addr('synth.fm')), isTrue);
        expect(registry.contains(_addr('synth.sampler')), isTrue);
      },
    );

    test('newSynth defaults are the right subclass', () {
      final va = controller.newSynth(SynthKind.va);
      final fm = controller.newSynth(SynthKind.fm);
      final sampler = controller.newSynth(SynthKind.sampler);
      Map<String, Object?> payloadOf(EntityAddress a) =>
          (registry.entityAt(a)!.payload as Map).cast<String, Object?>();
      expect(VaSynth.fromJson(payloadOf(va)), isA<VaSynth>());
      expect(FmSynth.fromJson(payloadOf(fm)), isA<FmSynth>());
      expect(SamplerSynth.fromJson(payloadOf(sampler)), isA<SamplerSynth>());
    });

    test('newFx creates the fx instance, records, selects', () {
      final address = controller.newFx(FxKind.phaser);
      expect(address, _addr('fx.phaser'));
      expect(controller.kindTagAt(address), 'phaser');
      expect(controller.selected, address);
      expect(recorded, hasLength(1));
    });

    test('newGroup creates a group folder in the namespace + records', () {
      final group = controller.newGroup('fx');
      expect(registry.groupAt(group), isNotNull);
      expect(group.kind, 'fx');
      expect(recorded, hasLength(1));
    });

    test('fresh names suffix to stay unique among siblings', () {
      final a = controller.newSynth(SynthKind.sine);
      final b = controller.newSynth(SynthKind.sine);
      expect(a, _addr('synth.sine'));
      expect(b, _addr('synth.sine_2'));
    });

    test('duplicate copies the payload to <name>_copy beside it + selects', () {
      registry.createEntity(_addr('fx.reverb'), payload: {'kind': 'lowpass'});

      final copy = controller.duplicate(_addr('fx.reverb'));

      expect(copy, _addr('fx.reverb_copy'));
      expect(controller.kindTagAt(copy!), 'lowpass');
      expect(controller.selected, copy);
    });

    test('duplicate of a missing entity is a no-op', () {
      expect(controller.duplicate(_addr('synth.nope')), isNull);
    });

    test('rename moves the entity (refactor) and keeps the selection', () {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      controller.select(_addr('synth.lead'));

      controller.rename(_addr('synth.lead'), 'Big Lead');

      expect(registry.contains(_addr('synth.lead')), isFalse);
      expect(registry.contains(_addr('synth.big_lead')), isTrue);
      expect(controller.selected, _addr('synth.big_lead'));
    });

    test('rename to a blank or unchanged slug is a no-op', () {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      controller.rename(_addr('synth.lead'), '   ');
      controller.rename(_addr('synth.lead'), 'lead');
      expect(registry.contains(_addr('synth.lead')), isTrue);
    });

    test('impactOf reports referents; delete removes and clears selection', () {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      // A voice that instantiates the synth — a referent that would be stranded.
      registry.createEntity(
        _addr('voice.bells'),
        payload: VoiceDefinition.internal(
          synth: _addr('synth.lead'),
          output: _addr('mix.master'),
        ),
      );
      controller.select(_addr('synth.lead'));

      final impact = controller.impactOf(_addr('synth.lead'));
      expect(impact.hasReferrers, isTrue);
      expect(impact.referrers, contains(_addr('voice.bells')));

      controller.delete(_addr('synth.lead'));
      expect(registry.contains(_addr('synth.lead')), isFalse);
      expect(controller.selected, isNull);
    });

    test('regroup re-parents within a kind; cross-kind is a no-op', () {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      registry.createGroup(_addr('synth.keys'));
      registry.createGroup(_addr('fx.bus'));

      // Cross-kind drop rejected.
      controller.regroup(_addr('synth.lead'), _addr('fx.bus'));
      expect(registry.contains(_addr('synth.lead')), isTrue);

      // Same-kind regroup into a group.
      controller.regroup(_addr('synth.lead'), _addr('synth.keys'));
      expect(registry.contains(_addr('synth.keys.lead')), isTrue);
      expect(registry.contains(_addr('synth.lead')), isFalse);
    });

    test('reorderBefore reorders siblings', () {
      registry.createEntity(
        _addr('synth.a'),
        payload: const SineSynth().toJson(),
      );
      registry.createEntity(
        _addr('synth.b'),
        payload: const SineSynth().toJson(),
      );
      registry.createEntity(
        _addr('synth.c'),
        payload: const SineSynth().toJson(),
      );
      expect(controller.synthTree.map((n) => n.name), ['a', 'b', 'c']);

      controller.reorderBefore(_addr('synth.c'), _addr('synth.a'));

      expect(controller.synthTree.map((n) => n.name), ['c', 'a', 'b']);
    });

    test('voices flattens the voice. namespace into read-only rows', () {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      registry.createEntity(
        _addr('voice.bells'),
        payload: VoiceDefinition.internal(
          synth: _addr('synth.lead'),
          output: _addr('mix.master'),
          color: 'voice3',
        ).toJson(),
      );
      registry.createEntity(
        _addr('voice.keys'),
        payload: VoiceDefinition.external(
          channel: 5,
          output: _addr('mix.master'),
        ).toJson(),
      );

      final voices = controller.voices;
      expect(voices.map((v) => v.name), containsAll(['bells', 'keys']));

      final bells = voices.firstWhere((v) => v.name == 'bells');
      expect(bells.kind, VoiceKind.internal);
      expect(bells.synth, _addr('synth.lead'));
      expect(bells.output, _addr('mix.master'));
      expect(bells.colorToken, 'voice3');

      final keys = voices.firstWhere((v) => v.name == 'keys');
      expect(keys.kind, VoiceKind.external);
      expect(keys.channel, 5);
    });

    test('rebind swaps the registry and clears selection', () {
      registry.createEntity(
        _addr('synth.lead'),
        payload: const VaSynth().toJson(),
      );
      controller.select(_addr('synth.lead'));
      expect(controller.selected, isNotNull);

      final next = ProjectRegistry();
      addTearDown(next.dispose);
      controller.rebind(registry: next, recordCommand: recorded.add);

      expect(controller.selected, isNull);
      expect(controller.synthTree, isEmpty);
      // Mutations on the old registry no longer notify.
      var notified = false;
      controller.addListener(() => notified = true);
      registry.createEntity(
        _addr('synth.x'),
        payload: const SineSynth().toJson(),
      );
      expect(notified, isFalse);
    });

    group('editor decode / update (issue #210)', () {
      test('synthAt decodes each synth kind; fxAt decodes an fx', () {
        registry.createEntity(
          _addr('synth.va'),
          payload: const VaSynth().toJson(),
        );
        registry.createEntity(
          _addr('synth.fm'),
          payload: const FmSynth(patchIndex: 3).toJson(),
        );
        registry.createEntity(
          _addr('fx.delay'),
          payload: const FxDefinition(kind: FxKind.lowpassDelay).toJson(),
        );

        expect(controller.synthAt(_addr('synth.va')), isA<VaSynth>());
        expect(
          (controller.synthAt(_addr('synth.fm'))! as FmSynth).patchIndex,
          3,
        );
        expect(controller.fxAt(_addr('fx.delay'))!.kind, FxKind.lowpassDelay);
        // Wrong-shape lookups return null rather than throw.
        expect(controller.synthAt(_addr('fx.delay')), isNull);
        expect(controller.fxAt(_addr('synth.va')), isNull);
        expect(controller.synthAt(_addr('synth.missing')), isNull);
      });

      test(
        'updateSynth writes the payload and records one journaled command',
        () {
          registry.createEntity(
            _addr('synth.va'),
            payload: const VaSynth().toJson(),
          );
          recorded.clear();

          controller.updateSynth(
            _addr('synth.va'),
            const VaSynth().copyWith(voiceCount: 12, gain: 0.5),
          );

          expect(recorded, hasLength(1));
          final stored = controller.synthAt(_addr('synth.va'))! as VaSynth;
          expect(stored.voiceCount, 12);
          expect(stored.gain, 0.5);
        },
      );

      test('updateFx writes the fx payload and records one command', () {
        registry.createEntity(
          _addr('fx.delay'),
          payload: const FxDefinition(kind: FxKind.lowpassDelay).toJson(),
        );
        recorded.clear();

        controller.updateFx(
          _addr('fx.delay'),
          const FxDefinition(
            kind: FxKind.lowpassDelay,
          ).withParam('tap1Time', 250),
        );

        expect(recorded, hasLength(1));
        expect(controller.fxAt(_addr('fx.delay'))!.params['tap1Time'], 250);
      });

      test('update on a missing entity is a no-op', () {
        controller.updateSynth(_addr('synth.ghost'), const VaSynth());
        expect(recorded, isEmpty);
      });
    });

    group('voice editing (issue #211)', () {
      void seedVoices() {
        registry.createEntity(
          _addr('synth.a'),
          payload: const SineSynth().toJson(),
        );
        registry.createEntity(
          _addr('synth.b'),
          payload: const VaSynth().toJson(),
        );
        registry.createEntity(
          _addr('voice.bass'),
          payload: VoiceDefinition.internal(
            synth: _addr('synth.a'),
            output: _addr('mix.master'),
            color: 'voice1',
          ).toJson(),
          references: {_addr('synth.a'), _addr('mix.master')},
        );
      }

      test('voiceAt decodes a voice; picker sources list the options', () {
        seedVoices();
        registry.createEntity(_addr('mix.drums'), payload: {'voice': 2});

        final voice = controller.voiceAt(_addr('voice.bass'))!;
        expect(voice.kind, VoiceKind.internal);
        expect(voice.synth, _addr('synth.a'));

        expect(controller.synthDefinitions, [
          _addr('synth.a'),
          _addr('synth.b'),
        ]);
        // Master is always offered first, then user buses in tree order.
        expect(controller.mixBuses, [_addr('mix.master'), _addr('mix.drums')]);
        // A wrong-shape lookup returns null rather than throwing.
        expect(controller.voiceAt(_addr('synth.a')), isNull);
      });

      test('newVoice adds an internal voice bound to the first synth', () {
        seedVoices();
        recorded.clear();

        final address = controller.newVoice();

        expect(recorded, hasLength(1));
        final voice = controller.voiceAt(address)!;
        expect(voice.kind, VoiceKind.internal);
        expect(voice.synth, _addr('synth.a'));
        expect(voice.output, _addr('mix.master'));
      });

      test('newVoice with no synths falls back to an external voice', () {
        registry.createEntity(
          _addr('voice.default'),
          payload: VoiceDefinition.external(
            channel: 1,
            output: _addr('mix.master'),
          ).toJson(),
        );

        final address = controller.newVoice();
        final voice = controller.voiceAt(address)!;
        expect(voice.kind, VoiceKind.external);
        expect(voice.channel, 1);
      });

      test('updateVoice re-points the synth and refreshes the back-refs', () {
        seedVoices();
        recorded.clear();

        controller.updateVoice(
          _addr('voice.bass'),
          controller
              .voiceAt(_addr('voice.bass'))!
              .copyWith(synth: _addr('synth.b')),
        );

        expect(recorded, hasLength(1));
        expect(
          controller.voiceAt(_addr('voice.bass'))!.synth,
          _addr('synth.b'),
        );
        // The delete-impact index followed the re-point: synth.a is now free,
        // synth.b is referenced by the voice.
        expect(controller.impactOf(_addr('synth.a')).hasReferrers, isFalse);
        expect(
          controller
              .impactOf(_addr('synth.b'))
              .referrers
              .map((r) => r.format()),
          contains('voice.bass'),
        );
      });

      test('updateVoice can switch kind internal → external', () {
        seedVoices();

        controller.updateVoice(
          _addr('voice.bass'),
          VoiceDefinition.external(
            channel: 7,
            output: _addr('mix.master'),
            color: 'voice1',
          ),
        );

        final voice = controller.voiceAt(_addr('voice.bass'))!;
        expect(voice.kind, VoiceKind.external);
        expect(voice.channel, 7);
        expect(voice.synth, isNull);
        // The old synth binding is dropped from the back-ref index.
        expect(controller.impactOf(_addr('synth.a')).hasReferrers, isFalse);
      });

      test('updateVoice on a missing voice is a no-op', () {
        controller.updateVoice(
          _addr('voice.ghost'),
          VoiceDefinition.external(channel: 1, output: _addr('mix.master')),
        );
        expect(recorded, isEmpty);
      });
    });
  });
}
