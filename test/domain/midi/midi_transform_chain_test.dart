import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';

MidiClip _clip(List<MidiNote> notes) =>
    MidiClip(name: 't', notes: notes, bars: 1);

void main() {
  group('MidiTransformChain', () {
    test('output passes notes through active transforms in order', () {
      final chain = MidiTransformChain(
        source: _clip(const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        ]),
        transforms: const [
          TransposeTransform(semitones: 2, label: '+2'),
          TransposeTransform(semitones: 3, label: '+3'),
        ],
      );

      expect(chain.output.single.pitch, 65);
    });

    test(
      'order matters: transpose-then-snap differs from snap-then-transpose',
      () {
        const source = MidiNote(pitch: 61, start: 0, duration: 1, velocity: 1);
        final snapThenTranspose = MidiTransformChain(
          source: _clip(const [source]),
          transforms: const [
            ScaleConformanceTransform(
              scale: MusicScale.dorian,
              tonic: 60,
              label: 'snap',
            ),
            TransposeTransform(semitones: 1, label: '+1'),
          ],
        );
        final transposeThenSnap = MidiTransformChain(
          source: _clip(const [source]),
          transforms: const [
            TransposeTransform(semitones: 1, label: '+1'),
            ScaleConformanceTransform(
              scale: MusicScale.dorian,
              tonic: 60,
              label: 'snap',
            ),
          ],
        );

        // snap(61) → 62 (D), then +1 → 63 (Eb).
        expect(snapThenTranspose.output.single.pitch, 63);
        // +1 → 62 (D, already in scale), snap → 62.
        expect(transposeThenSnap.output.single.pitch, 62);
      },
    );

    test('setActiveAt skips the transform, notifies, and bumps version', () {
      final chain = MidiTransformChain(
        source: _clip(const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
        ]),
        transforms: const [TransposeTransform(semitones: 5, label: '+5')],
      );
      expect(chain.output.single.pitch, 65);

      var notifications = 0;
      chain.addListener(() => notifications++);
      final v0 = chain.version;

      chain.setActiveAt(0, false);

      expect(notifications, 1);
      expect(chain.version, v0 + 1);
      expect(chain.transforms.single.active, isFalse);
      expect(chain.output.single.pitch, 60);
    });

    test('idempotent setActiveAt does not notify', () {
      final chain = MidiTransformChain(
        source: _clip(const []),
        transforms: const [TransposeTransform(semitones: 1, label: '+1')],
      );
      var notifications = 0;
      chain.addListener(() => notifications++);
      chain.setActiveAt(0, true); // already true
      expect(notifications, 0);
      expect(chain.version, 0);
    });

    test('add / removeAt / reorder mutate and notify', () {
      final chain = MidiTransformChain(
        source: _clip(const []),
        transforms: const [
          TransposeTransform(semitones: 1, label: 'a'),
          TransposeTransform(semitones: 2, label: 'b'),
        ],
      );
      var notifications = 0;
      chain.addListener(() => notifications++);

      chain.add(const StubTransform(kind: MidiTransformKind.time, label: 'c'));
      expect(chain.transforms.length, 3);
      expect(notifications, 1);

      chain.removeAt(0);
      expect(chain.transforms.length, 2);
      expect(chain.transforms[0].label, 'b');
      expect(notifications, 2);

      chain.reorder(0, 2);
      expect(chain.transforms.map((t) => t.label), ['c', 'b']);
      expect(notifications, 3);
    });

    test('reorder is a no-op when from == to', () {
      final chain = MidiTransformChain(
        source: _clip(const []),
        transforms: const [TransposeTransform(semitones: 1, label: 'a')],
      );
      var notifications = 0;
      chain.addListener(() => notifications++);
      chain.reorder(0, 0);
      expect(notifications, 0);
    });
  });
}
