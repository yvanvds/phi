import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/transform_param.dart';
import 'package:phi/domain/midi/transforms/conditional_muting_transform.dart';
import 'package:phi/domain/midi/transforms/humanization_transform.dart';
import 'package:phi/domain/midi/transforms/inversion_transform.dart';
import 'package:phi/domain/midi/transforms/loop_transform.dart';
import 'package:phi/domain/midi/transforms/note_condition.dart';
import 'package:phi/domain/midi/transforms/probabilistic_skip_repeat_transform.dart';
import 'package:phi/domain/midi/transforms/quantization_transform.dart';
import 'package:phi/domain/midi/transforms/reverse_transform.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/stretch_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';

/// The parameter-mutation seam (issue #71): every scalar transform exposes its
/// editable params as descriptors and round-trips them through [withParam].
void main() {
  /// The value of the param named [name], read back from a fresh descriptor
  /// list — proving the edit landed and the descriptor reflects it.
  num paramValue(MidiTransform t, String name) =>
      switch (t.params.firstWhere((p) => p.name == name)) {
        IntParam(:final value) => value,
        DoubleParam(:final value) => value,
      };

  group('round-trip per transform', () {
    test('transpose: semitones', () {
      const t = TransposeTransform(semitones: 12, label: 'l', active: false);
      expect(paramValue(t, 'semitones'), 12);

      final edited = t.withParam('semitones', -7);
      expect(paramValue(edited, 'semitones'), -7);
      expect(edited.label, 'l');
      expect(edited.active, isFalse);
    });

    test('stretch: factor', () {
      const t = StretchTransform(factor: 2, label: 'l');
      expect(paramValue(t, 'factor'), 2);
      expect(paramValue(t.withParam('factor', 0.5), 'factor'), 0.5);
    });

    test('quantize: grid and gravity, each preserving the other', () {
      const t = QuantizationTransform(gravity: 1, label: 'l', grid: 0.25);
      final edited = t.withParam('grid', 0.5).withParam('gravity', 0.6);
      expect(paramValue(edited, 'grid'), 0.5);
      expect(paramValue(edited, 'gravity'), 0.6);
    });

    test('invert: axis', () {
      const t = InversionTransform(axis: 60, label: 'l');
      expect(paramValue(t.withParam('axis', 66.5), 'axis'), 66.5);
    });

    test('reverse: window', () {
      const t = ReverseTransform(lengthBeats: 16, label: 'l');
      expect(paramValue(t.withParam('window', 8), 'window'), 8);
    });

    test('loop: length, repeats, phase — untilBeat survives untouched', () {
      const t = LoopTransform(loopLengthBeats: 16, label: 'l', untilBeat: 64);
      // A null repeatCount (play once) is presented as 1.
      expect(paramValue(t, 'repeats'), 1);

      final edited = t
          .withParam('length', 8)
          .withParam('repeats', 4)
          .withParam('phase', 0.5);
      expect(paramValue(edited, 'length'), 8);
      expect(paramValue(edited, 'repeats'), 4);
      expect(paramValue(edited, 'phase'), 0.5);
      expect(edited.untilBeat, 64);
    });

    test('humanize: ranges and seed', () {
      const t = HumanizationTransform(label: 'l');
      final edited = t
          .withParam('time ±', 0.05)
          .withParam('velocity ±', 0.2)
          .withParam('seed', 7);
      expect(paramValue(edited, 'time ±'), 0.05);
      expect(paramValue(edited, 'velocity ±'), 0.2);
      expect(paramValue(edited, 'seed'), 7);
    });

    test('skip · repeat: probabilities, echoes, seed', () {
      const t = ProbabilisticSkipRepeatTransform(label: 'l');
      final edited = t
          .withParam('skip', 0.3)
          .withParam('repeat', 0.6)
          .withParam('echoes', 3)
          .withParam('seed', 42);
      expect(paramValue(edited, 'skip'), 0.3);
      expect(paramValue(edited, 'repeat'), 0.6);
      expect(paramValue(edited, 'echoes'), 3);
      expect(paramValue(edited, 'seed'), 42);
    });

    test('scale: tonic — the tuning survives untouched', () {
      final t = ScaleConformanceTransform.diatonic(
        scale: MusicScale.dorian,
        tonic: 60,
        label: 'l',
      );
      final edited = t.withParam('tonic', 62);
      expect(paramValue(edited, 'tonic'), 62);
      expect(edited.tuning.degreesCents, t.tuning.degreesCents);
    });
  });

  group('seam contract', () {
    test('unknown names throw instead of silently dropping the edit', () {
      const t = TransposeTransform(semitones: 0, label: 'l');
      expect(() => t.withParam('nope', 1), throwsArgumentError);
    });

    test('data-model transforms expose no scalar params (issue #95)', () {
      // Its behaviour lives in a declarative NoteCondition edited by a typed
      // editor (issue #109), not in the scalar withParam seam.
      const t = ConditionalMutingTransform(
        condition: NoteConditionGroup.empty(),
        label: 'l',
      );
      expect(t.params, isEmpty);
      expect(() => t.withParam('anything', 1), throwsArgumentError);
    });
  });

  group('chain integration', () {
    test('replaceAt with an edited transform changes the chain output', () {
      final chain = MidiTransformChain(
        source: MidiClip(
          notes: const [
            MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
          ],
          bars: 1,
        ),
        transforms: const [TransposeTransform(semitones: 12, label: 'l')],
      );
      expect(chain.output.single.pitch, 72);

      final versionBefore = chain.version;
      chain.replaceAt(0, chain.transforms.single.withParam('semitones', -12));

      expect(chain.output.single.pitch, 48);
      expect(chain.version, greaterThan(versionBefore));
      chain.dispose();
    });
  });
}
