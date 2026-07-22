import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/state_slice_category.dart';
import 'package:phi/domain/state_machine/slices/state_slices.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';

void main() {
  final drums = EntityAddress.parse('clip.drums');
  final pads = EntityAddress.parse('mix.pads');
  final drum = EntityAddress.parse('domain.drum');

  StateSlices fullSlices() => StateSlices(
    clips: [ClipSliceEntry(clip: drums, loop: false)],
    mix: [MixSliceEntry(bus: pads, volume: 0.4)],
    variables: const {'section': 'a'},
    tempos: [TempoSliceEntry(domain: drum, bpm: 124)],
  );

  group('StateSlices JSON round-trip', () {
    test('all four captured categories round-trip identically', () {
      final slices = fullSlices();
      expect(StateSlices.fromJson(slices.toJson()), slices);
    });

    test('uncaptured categories are omitted and stay null', () {
      const slices = StateSlices.empty;
      expect(slices.toJson(), isEmpty);
      final decoded = StateSlices.fromJson(slices.toJson());
      expect(decoded, slices);
      expect(decoded.isEmpty, isTrue);
    });

    test('captured-but-empty is distinct from uncaptured', () {
      // "No clips playing" is a meaningful capture — it must not collapse to
      // "clips untouched" across a save/load (design §4).
      const slices = StateSlices(clips: []);
      final decoded = StateSlices.fromJson(slices.toJson());
      expect(decoded.clips, isEmpty);
      expect(decoded.clips, isNotNull);
      expect(decoded, isNot(StateSlices.empty));
    });

    test('a non-string variable value throws', () {
      expect(
        () => StateSlices.fromJson(const {
          'variables': {'section': 3},
        }),
        throwsFormatException,
      );
    });
  });

  group('StateSlices references', () {
    test('collects clip, bus and domain addresses; variables contribute '
        'nothing', () {
      expect(fullSlices().references, {drums, pads, drum});
      expect(StateSlices.empty.references, isEmpty);
    });

    test('withReferenceUpdated repoints entries per category', () {
      final renamed = EntityAddress.parse('clip.percussion');
      final repointed = fullSlices().withReferenceUpdated(drums, renamed);
      expect(repointed.clips!.single.clip, renamed);
      expect(repointed.clips!.single.loop, isFalse);
      // Other categories untouched.
      expect(repointed.mix!.single.bus, pads);
      expect(repointed.tempos!.single.domain, drum);
      // The inverse restores the original.
      expect(repointed.withReferenceUpdated(renamed, drums), fullSlices());
    });
  });

  group('StateSlices copyWith', () {
    test('captures and clears categories independently', () {
      final captured = StateSlices.empty.copyWith(
        clips: [ClipSliceEntry(clip: drums)],
      );
      expect(captured.clips, hasLength(1));
      expect(captured.mix, isNull);

      final cleared = captured.copyWith(clearClips: true);
      expect(cleared.clips, isNull);
      expect(cleared.isEmpty, isTrue);
    });
  });

  group('StateSlices category helpers (issue #242)', () {
    test('isCaptured tracks each category, counting captured-but-empty', () {
      expect(
        StateSliceCategory.values.where(StateSlices.empty.isCaptured),
        isEmpty,
      );
      final full = fullSlices();
      expect(StateSliceCategory.values.where(full.isCaptured), hasLength(4));
      const emptyClips = StateSlices(clips: []);
      expect(emptyClips.isCaptured(StateSliceCategory.clips), isTrue);
      expect(emptyClips.isCaptured(StateSliceCategory.mix), isFalse);
    });

    test('cleared un-captures exactly the one category', () {
      final cleared = fullSlices().cleared(StateSliceCategory.mix);
      expect(cleared.mix, isNull);
      expect(cleared.clips, isNotNull);
      expect(cleared.variables, isNotNull);
      expect(cleared.tempos, isNotNull);
    });
  });

  group('StateSlices per-entry editing (issue #242)', () {
    final percussion = EntityAddress.parse('clip.percussion');

    test('withoutClip removes one entry, keeping the others', () {
      final two = fullSlices().copyWith(
        clips: [
          ClipSliceEntry(clip: drums, loop: false),
          ClipSliceEntry(clip: percussion),
        ],
      );
      final edited = two.withoutClip(drums);
      expect(edited.clips, [ClipSliceEntry(clip: percussion)]);
      // Other categories are untouched.
      expect(edited.mix, two.mix);
      expect(edited.variables, two.variables);
      expect(edited.tempos, two.tempos);
    });

    test('removing the last entry keeps the category captured-but-empty', () {
      final edited = fullSlices()
          .withoutClip(drums)
          .withoutBus(pads)
          .withoutVariable('section')
          .withoutTempo(drum);
      expect(edited.clips, isNotNull);
      expect(edited.clips, isEmpty);
      expect(edited.mix, isNotNull);
      expect(edited.mix, isEmpty);
      expect(edited.variables, isNotNull);
      expect(edited.variables, isEmpty);
      expect(edited.tempos, isNotNull);
      expect(edited.tempos, isEmpty);
      // The edit never collapses "captured empty" into "uncaptured".
      expect(edited.isEmpty, isFalse);
    });

    test('removing from an uncaptured category or an absent entry is the '
        'identity', () {
      final slices = fullSlices();
      expect(
        identical(StateSlices.empty.withoutClip(drums), StateSlices.empty),
        isTrue,
      );
      expect(identical(slices.withoutClip(percussion), slices), isTrue);
      expect(identical(slices.withoutBus(drums), slices), isTrue);
      expect(identical(slices.withoutVariable('missing'), slices), isTrue);
      expect(identical(slices.withoutTempo(pads), slices), isTrue);
    });

    test('per-entry edits round-trip through JSON', () {
      final edited = fullSlices().withoutVariable('section').withoutClip(drums);
      expect(StateSlices.fromJson(edited.toJson()), edited);
    });
  });
}
