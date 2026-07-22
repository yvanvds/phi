import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/project_command.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/state_slice_resolution.dart';
import 'package:phi/domain/state_machine/slices/state_slices.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';
import 'package:phi/domain/state_machine/state_transition.dart';
import 'package:phi/domain/state_machine/store/state_seed.dart';
import 'package:phi/engine/bridge/code_evaluator.dart';
import 'package:phi/engine/state/state_application_engine.dart';
import 'package:phi/engine/state/state_application_notice.dart';
import 'package:phi/engine/state/state_machine_controller.dart';
import 'package:phi/engine/state/state_slice_applier.dart';

import '../test_doubles/fake_code_evaluator.dart';

/// A [StateSliceApplier] recording every call in order — the fake "owning
/// controllers" the application engine writes through (issue #243).
class _RecordingApplier implements StateSliceApplier {
  final List<String> calls = [];

  /// Variable names [applyVariable] reports unappliable.
  final Set<String> undefinedVariables = {};

  /// Clip addresses [applyClips] reports unstartable.
  final Set<EntityAddress> unplayableClips = {};

  /// When set, every call throws — the unexpected-error degradation path.
  Object? throwOnCall;

  void _record(String call) {
    calls.add(call);
    final error = throwOnCall;
    if (error != null) throw error;
  }

  @override
  bool applyVariable(String name, String value) {
    _record('var:$name=$value');
    return !undefinedVariables.contains(name);
  }

  @override
  void applyTempo(EntityAddress domain, double bpm) =>
      _record('tempo:${domain.format()}@$bpm');

  @override
  void applyMix(
    EntityAddress bus, {
    required double volume,
    required bool muted,
  }) => _record('mix:${bus.format()}@$volume${muted ? '/muted' : ''}');

  @override
  Set<EntityAddress> applyClips(List<ClipSliceEntry> entries) {
    _record('clips:[${entries.map((e) => e.clip.format()).join(',')}]');
    return {
      for (final entry in entries)
        if (unplayableClips.contains(entry.clip)) entry.clip,
    };
  }
}

/// The journal-free ordered application engine (design state-graph §4, §8
/// decision 2; issue #243): variables → tempos → mix → clips → on-enter
/// script, uncaptured categories untouched, every degradation a notice and
/// never a crash, and nothing journaled across applications.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  late _RecordingApplier applier;
  late FakeCodeEvaluator evaluator;
  late List<StateApplicationNotice> notices;
  late Map<EntityAddress, String> scripts;

  StateApplicationEngine build({bool withEvaluator = true}) =>
      StateApplicationEngine(
        applier: applier,
        evaluator: () => withEvaluator ? evaluator : null,
        scriptSourceOf: (code) => scripts[code],
        onNotice: notices.add,
      );

  /// Resolve [slices] with every referent present.
  StateSliceResolution resolved(StateSlices slices) =>
      StateSliceResolution.of(slices, exists: (_) => true);

  final state = EntityAddress.parse('state.verse');

  setUp(() {
    applier = _RecordingApplier();
    evaluator = FakeCodeEvaluator(
      onEvaluate: (_) => applier.calls.add('script'),
    );
    notices = [];
    scripts = {};
  });

  group('ordered application', () {
    test(
      'applies variables → tempos → mix → clips → on-enter script',
      () async {
        scripts[addr('code.enter')] = 'phi.log("verse")';
        final slices = StateSlices(
          clips: [ClipSliceEntry(clip: addr('clip.drums'), loop: false)],
          mix: [MixSliceEntry(bus: addr('mix.pads'), volume: 0.4, muted: true)],
          variables: const {'section': 'a', 'mode': 'lead'},
          tempos: [TempoSliceEntry(domain: addr('domain.drum'), bpm: 100)],
        );

        await build().enterState(
          state: state,
          resolution: resolved(slices),
          onEnter: addr('code.enter'),
        );

        expect(applier.calls, [
          'var:section=a',
          'var:mode=lead',
          'tempo:domain.drum@100.0',
          'mix:mix.pads@0.4/muted',
          'clips:[clip.drums]',
          'script',
        ]);
        expect(evaluator.calls, ['phi.log("verse")']);
        expect(notices, isEmpty);
      },
    );

    test('multiple entries per category apply in captured order', () async {
      final slices = StateSlices(
        tempos: [
          TempoSliceEntry(domain: addr('domain.drum'), bpm: 100),
          TempoSliceEntry(domain: addr('domain.pad'), bpm: 60),
        ],
        mix: [
          MixSliceEntry(bus: addr('mix.a'), volume: 1),
          MixSliceEntry(bus: addr('mix.b'), volume: 0.5),
        ],
      );

      await build().enterState(state: state, resolution: resolved(slices));

      expect(applier.calls, [
        'tempo:domain.drum@100.0',
        'tempo:domain.pad@60.0',
        'mix:mix.a@1.0',
        'mix:mix.b@0.5',
      ]);
    });
  });

  group('partial application', () {
    test('uncaptured categories touch nothing — including clips', () async {
      final slices = StateSlices(
        mix: [MixSliceEntry(bus: addr('mix.pads'), volume: 0.4)],
      );

      await build().enterState(state: state, resolution: resolved(slices));

      // No variables, no tempos, and crucially no `clips:` call — an
      // uncaptured clips category must not stop the playing set.
      expect(applier.calls, ['mix:mix.pads@0.4']);
      expect(notices, isEmpty);
    });

    test(
      'captured-but-empty clips still applies (stops the playing set)',
      () async {
        const slices = StateSlices(clips: []);

        await build().enterState(state: state, resolution: resolved(slices));

        expect(applier.calls, ['clips:[]']);
        expect(notices, isEmpty);
      },
    );

    test('all-uncaptured slices with no script apply nothing', () async {
      await build().enterState(
        state: state,
        resolution: resolved(StateSlices.empty),
      );

      expect(applier.calls, isEmpty);
      expect(evaluator.calls, isEmpty);
      expect(notices, isEmpty);
    });
  });

  group('graceful degradation', () {
    test('deleted referents are surfaced and the remainder applies', () async {
      final slices = StateSlices(
        mix: [
          MixSliceEntry(bus: addr('mix.gone'), volume: 0.2),
          MixSliceEntry(bus: addr('mix.pads'), volume: 0.4),
        ],
        tempos: [TempoSliceEntry(domain: addr('domain.drum'), bpm: 100)],
      );
      final resolution = StateSliceResolution.of(
        slices,
        exists: (address) => address != addr('mix.gone'),
      );

      await build().enterState(state: state, resolution: resolution);

      expect(applier.calls, ['tempo:domain.drum@100.0', 'mix:mix.pads@0.4']);
      expect(notices, hasLength(1));
      expect(notices.single.state, state);
      expect(notices.single.message, contains('mix.gone'));
    });

    test(
      'an undefined variable is skipped with a notice; the rest apply',
      () async {
        applier.undefinedVariables.add('gone');
        const slices = StateSlices(variables: {'gone': 'x', 'section': 'a'});

        await build().enterState(state: state, resolution: resolved(slices));

        expect(applier.calls, ['var:gone=x', 'var:section=a']);
        expect(notices, hasLength(1));
        expect(notices.single.message, contains('gone'));
        expect(notices.single.message, isNot(contains('section')));
      },
    );

    test('an unstartable clip is skipped with a notice', () async {
      applier.unplayableClips.add(addr('clip.broken'));
      final slices = StateSlices(
        clips: [
          ClipSliceEntry(clip: addr('clip.broken')),
          ClipSliceEntry(clip: addr('clip.drums')),
        ],
      );

      await build().enterState(state: state, resolution: resolved(slices));

      expect(notices, hasLength(1));
      expect(notices.single.message, contains('clip.broken'));
      expect(notices.single.message, isNot(contains('clip.drums')));
    });

    test('a throwing controller degrades to a notice and later categories '
        'still apply', () async {
      applier.throwOnCall = StateError('tempo port exploded');
      final slices = StateSlices(
        tempos: [TempoSliceEntry(domain: addr('domain.drum'), bpm: 100)],
        mix: [MixSliceEntry(bus: addr('mix.pads'), volume: 0.4)],
      );

      // Both categories were attempted; both throws became notices.
      await build().enterState(state: state, resolution: resolved(slices));

      expect(applier.calls, ['tempo:domain.drum@100.0', 'mix:mix.pads@0.4']);
      expect(notices, hasLength(2));
      expect(notices.first.message, contains('tempo port exploded'));
    });
  });

  group('on-enter script', () {
    test(
      'a missing code reference skips with a notice, never evaluating',
      () async {
        await build().enterState(
          state: state,
          resolution: resolved(StateSlices.empty),
          onEnter: addr('code.gone'),
        );

        expect(evaluator.calls, isEmpty);
        expect(notices, hasLength(1));
        expect(notices.single.message, contains('code.gone'));
        expect(notices.single.message, contains('missing'));
      },
    );

    test('no wired evaluator skips with a notice', () async {
      scripts[addr('code.enter')] = 'x = 1';

      await build(withEvaluator: false).enterState(
        state: state,
        resolution: resolved(StateSlices.empty),
        onEnter: addr('code.enter'),
      );

      expect(notices, hasLength(1));
      expect(notices.single.message, contains('no evaluator'));
    });

    test('a rejected evaluation surfaces the error as a notice', () async {
      scripts[addr('code.enter')] = 'not python';
      evaluator.nextOutcome = const EvalOutcome.failed('SyntaxError');

      await build().enterState(
        state: state,
        resolution: resolved(StateSlices.empty),
        onEnter: addr('code.enter'),
      );

      expect(notices, hasLength(1));
      expect(notices.single.message, contains('SyntaxError'));
    });

    test('a throwing evaluator degrades to a notice, never a crash', () async {
      scripts[addr('code.enter')] = 'x = 1';
      final throwing = _ThrowingEvaluator();

      final engine = StateApplicationEngine(
        applier: applier,
        evaluator: () => throwing,
        scriptSourceOf: (code) => scripts[code],
        onNotice: notices.add,
      );
      await engine.enterState(
        state: state,
        resolution: resolved(StateSlices.empty),
        onEnter: addr('code.enter'),
      );

      expect(notices, hasLength(1));
      expect(notices.single.message, contains('kernel gone'));
    });
  });

  group('journal-free across applications (§8 decision 2)', () {
    test('firing into a sliced state applies without journaling or touching '
        'payloads', () async {
      final registry = ProjectRegistry();
      final intro = introStateDocument();
      registry.createEntity(
        introStateAddress,
        payload: intro.toJson(),
        references: intro.references,
      );
      final verse = verseStateDocument().copyWith(
        slices: StateSlices(
          variables: const {'section': 'b'},
          mix: [MixSliceEntry(bus: addr('mix.pads'), volume: 0.4)],
          tempos: [TempoSliceEntry(domain: addr('domain.drum'), bpm: 100)],
          clips: [ClipSliceEntry(clip: addr('clip.drums'))],
        ),
        onEnter: addr('code.enter'),
      );
      registry.createEntity(
        verseStateAddress,
        payload: verse.toJson(),
        references: verse.references,
      );
      // The slice referents exist, so resolution drops nothing.
      for (final dotted in [
        'mix.pads',
        'domain.drum',
        'clip.drums',
        'code.enter',
      ]) {
        registry.createEntity(addr(dotted));
      }
      scripts[addr('code.enter')] = 'x = 1';

      final recorded = <ProjectCommand>[];
      final controller = StateMachineController(
        registry: registry,
        recordCommand: recorded.add,
      );
      final application = build();
      controller.onStateEntered = (entered) => application.enterState(
        state: entered,
        resolution: controller.resolveSlicesOf(entered),
        onEnter: controller.documentOf(entered)?.onEnter,
      );
      final payloadBefore = controller.documentOf(verseStateAddress);
      recorded.clear();

      controller.fire(
        StateTransition(source: introStateAddress, target: verseStateAddress),
      );
      await pumpEventQueue();

      // The whole state applied…
      expect(applier.calls, [
        'var:section=b',
        'tempo:domain.drum@100.0',
        'mix:mix.pads@0.4',
        'clips:[clip.drums]',
        'script',
      ]);
      // …and nothing was authored: no commands, payloads untouched.
      expect(recorded, isEmpty);
      expect(controller.documentOf(verseStateAddress), payloadBefore);
      expect(notices, isEmpty);

      controller.dispose();
      registry.dispose();
    });
  });
}

/// An evaluator whose [evaluate] throws — the unexpected-kernel-error path.
class _ThrowingEvaluator implements CodeEvaluator {
  @override
  Future<EvalOutcome> evaluate(String source) async =>
      throw StateError('kernel gone');

  @override
  Stream<EvalEvent> get events => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
