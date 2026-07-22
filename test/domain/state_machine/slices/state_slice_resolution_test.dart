import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/state_machine/slices/clip_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/mix_slice_entry.dart';
import 'package:phi/domain/state_machine/slices/state_slice_resolution.dart';
import 'package:phi/domain/state_machine/slices/state_slices.dart';
import 'package:phi/domain/state_machine/slices/tempo_slice_entry.dart';

/// The apply-time partition of captured slices into applicable entries and
/// dangling (deleted-referent) addresses (issue #242): a slice referencing a
/// deleted clip applies the rest and surfaces the missing address for the
/// notice (#243 consumes this).
void main() {
  final drums = EntityAddress.parse('clip.drums');
  final ghost = EntityAddress.parse('clip.ghost');
  final pads = EntityAddress.parse('mix.pads');
  final gone = EntityAddress.parse('mix.gone');
  final drum = EntityAddress.parse('domain.drum');

  StateSlices slices() => StateSlices(
    clips: [
      ClipSliceEntry(clip: drums, loop: false),
      ClipSliceEntry(clip: ghost),
    ],
    mix: [
      MixSliceEntry(bus: pads, volume: 0.4),
      MixSliceEntry(bus: gone, volume: 0.7, muted: true),
    ],
    variables: const {'section': 'a'},
    tempos: [TempoSliceEntry(domain: drum, bpm: 124)],
  );

  test('everything resolving keeps the slices intact with nothing missing', () {
    final resolution = StateSliceResolution.of(slices(), exists: (_) => true);
    expect(resolution.applicable, slices());
    expect(resolution.missing, isEmpty);
    expect(resolution.hasMissing, isFalse);
  });

  test(
    'a deleted referent drops only its entry and is surfaced as missing',
    () {
      final live = {drums, pads, drum};
      final resolution = StateSliceResolution.of(
        slices(),
        exists: live.contains,
      );
      expect(resolution.applicable.clips, [
        ClipSliceEntry(clip: drums, loop: false),
      ]);
      expect(resolution.applicable.mix, [
        MixSliceEntry(bus: pads, volume: 0.4),
      ]);
      expect(resolution.applicable.tempos, slices().tempos);
      expect(resolution.missing, {ghost, gone});
      expect(resolution.hasMissing, isTrue);
    },
  );

  test('variables are names, not entities — always applicable', () {
    final resolution = StateSliceResolution.of(slices(), exists: (_) => false);
    expect(resolution.applicable.variables, const {'section': 'a'});
    // Every addressed entry dropped, but the categories stay captured-empty:
    // the state still constrains what it captured.
    expect(resolution.applicable.clips, isEmpty);
    expect(resolution.applicable.clips, isNotNull);
    expect(resolution.applicable.mix, isEmpty);
    expect(resolution.applicable.tempos, isEmpty);
    expect(resolution.missing, {drums, ghost, pads, gone, drum});
  });

  test('uncaptured categories stay uncaptured through resolution', () {
    final resolution = StateSliceResolution.of(
      StateSlices.empty,
      exists: (_) => false,
    );
    expect(resolution.applicable, StateSlices.empty);
    expect(resolution.missing, isEmpty);
  });
}
