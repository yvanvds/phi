import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/runtime/runtime_variable_registry.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/engine/state/engine_state_slice_applier.dart';

/// The production [EngineStateSliceApplier] (issue #243): variables through a
/// real [RuntimeVariableRegistry] with honest applied/skipped reporting,
/// tempo + mix threaded to the owning-controller closures, and clips brought
/// to play/stop-to-match against the live playing set.
void main() {
  EntityAddress addr(String dotted) => EntityAddress.parse(dotted);

  group('variables through the runtime registry', () {
    late RuntimeVariableRegistry variables;
    late EngineStateSliceApplier applier;

    setUp(() {
      variables = RuntimeVariableRegistry();
      variables.define(name: 'section', values: ['a', 'b'], current: 'a');
      applier = EngineStateSliceApplier(
        variables: () => variables,
        domainTempo: (_, _) {},
        mixLevel: (_, {required volume, required muted}) {},
        playingClips: () => const [],
        playClip: (_) => true,
        stopClip: (_) {},
      );
    });

    tearDown(() => variables.dispose());

    test('sets a defined variable to a candidate value', () {
      expect(applier.applyVariable('section', 'b'), isTrue);
      expect(variables.byName('section')!.current, 'b');
    });

    test('an already-current value applies as a clean no-op', () {
      // `setValue` returns false here, but that is not a degradation — the
      // captured value already holds.
      expect(applier.applyVariable('section', 'a'), isTrue);
      expect(variables.byName('section')!.current, 'a');
    });

    test('an undefined name reports unapplied', () {
      expect(applier.applyVariable('gone', 'a'), isFalse);
    });

    test('a non-candidate value reports unapplied and moves nothing', () {
      expect(applier.applyVariable('section', 'z'), isFalse);
      expect(variables.byName('section')!.current, 'a');
    });
  });

  group('tempos and mix through the owning-controller closures', () {
    test('threads the domain address + bpm and the bus levels through', () {
      final calls = <String>[];
      final applier = EngineStateSliceApplier(
        variables: RuntimeVariableRegistry.new,
        domainTempo: (domain, bpm) => calls.add('${domain.format()}@$bpm'),
        mixLevel: (bus, {required volume, required muted}) =>
            calls.add('${bus.format()}@$volume/$muted'),
        playingClips: () => const [],
        playClip: (_) => true,
        stopClip: (_) {},
      );

      applier.applyTempo(addr('domain.drum'), 100);
      applier.applyMix(addr('mix.pads'), volume: 0.4, muted: true);

      expect(calls, ['domain.drum@100.0', 'mix.pads@0.4/true']);
    });
  });

  group('clips — play/stop to match', () {
    test('stops unlisted playing clips, plays the captured set, reports the '
        'unstartable, and never touches the rest', () {
      final played = <ClipSliceEntry>[];
      final stopped = <EntityAddress>[];
      final applier = EngineStateSliceApplier(
        variables: RuntimeVariableRegistry.new,
        domainTempo: (_, _) {},
        mixLevel: (_, {required volume, required muted}) {},
        playingClips: () => [
          ClipSliceEntry(clip: addr('clip.stale')),
          ClipSliceEntry(clip: addr('clip.bass')),
        ],
        playClip: (entry) {
          played.add(entry);
          return entry.clip != addr('clip.broken');
        },
        stopClip: stopped.add,
      );

      final skipped = applier.applyClips([
        ClipSliceEntry(clip: addr('clip.bass'), loop: false),
        ClipSliceEntry(clip: addr('clip.drums')),
        ClipSliceEntry(clip: addr('clip.broken')),
      ]);

      // `clip.stale` was playing but not captured — stopped. `clip.bass` was
      // captured too, so it stays. Nothing else was touched.
      expect(stopped, [addr('clip.stale')]);
      // Every captured entry was brought to play, loop flags intact and in
      // captured order; the unstartable one is reported back.
      expect(played, [
        ClipSliceEntry(clip: addr('clip.bass'), loop: false),
        ClipSliceEntry(clip: addr('clip.drums')),
        ClipSliceEntry(clip: addr('clip.broken')),
      ]);
      expect(skipped, {addr('clip.broken')});
    });

    test('a captured-but-empty list stops everything playing', () {
      final stopped = <EntityAddress>[];
      final applier = EngineStateSliceApplier(
        variables: RuntimeVariableRegistry.new,
        domainTempo: (_, _) {},
        mixLevel: (_, {required volume, required muted}) {},
        playingClips: () => [
          ClipSliceEntry(clip: addr('clip.drums')),
          ClipSliceEntry(clip: addr('clip.bass')),
        ],
        playClip: (_) => true,
        stopClip: stopped.add,
      );

      final skipped = applier.applyClips(const []);

      expect(stopped, [addr('clip.drums'), addr('clip.bass')]);
      expect(skipped, isEmpty);
    });
  });
}
