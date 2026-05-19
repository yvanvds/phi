import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip_seed.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';

void main() {
  group('phraseA', () {
    test('has 10 notes spanning 4 bars', () {
      final clip = phraseA();
      expect(clip.notes, hasLength(10));
      expect(clip.bars, 4);
      expect(clip.totalBeats, 16);
    });

    test('opens with C4 at beat 0', () {
      final clip = phraseA();
      final first = clip.notes.first;
      expect(first.pitch, 60);
      expect(first.start, 0);
    });

    test('every note fits inside the clip', () {
      final clip = phraseA();
      for (final n in clip.notes) {
        expect(n.start + n.duration, lessThanOrEqualTo(clip.totalBeats));
      }
    });
  });

  group('defaultDemoChain', () {
    test('has eight transforms with the two working ones first', () {
      final chain = defaultDemoChain();
      expect(chain.transforms, hasLength(8));
      expect(chain.transforms[0], isA<ScaleConformanceTransform>());
      expect(chain.transforms[1], isA<TransposeTransform>());
    });

    test('six are active, two structural ones are inactive', () {
      final chain = defaultDemoChain();
      final inactive = chain.transforms.where((t) => !t.active).toList();
      expect(inactive, hasLength(2));
      for (final t in inactive) {
        expect(t.kind, MidiTransformKind.struct);
      }
    });
  });
}
