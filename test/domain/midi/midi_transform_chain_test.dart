import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/midi_transform_kind.dart';
import 'package:phi/domain/midi/music_scale.dart';
import 'package:phi/domain/midi/transforms/inversion_transform.dart';
import 'package:phi/domain/midi/transforms/scale_conformance_transform.dart';
import 'package:phi/domain/midi/transforms/spectral_mapping_transform.dart';
import 'package:phi/domain/midi/transforms/split_voice.dart';
import 'package:phi/domain/midi/transforms/splitting_transform.dart';
import 'package:phi/domain/midi/transforms/stub_transform.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/midi/transforms/velocity_to_parameter_transform.dart';
import 'package:phi/domain/midi/transforms/voice_routing_rule.dart';
import 'package:phi/domain/midi/transforms/voice_routing_transform.dart';

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

    test('inversion + spectral mapping slot into the chain and compose', () {
      // A source note at C4, mirrored around C4 (identity for that note),
      // then remapped 60→72 by the spectral table. Confirms both new pitch
      // transforms honour list order alongside the existing ones.
      final chain = MidiTransformChain(
        source: _clip(const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1),
          MidiNote(pitch: 64, start: 1, duration: 1, velocity: 1),
        ]),
        transforms: const [
          InversionTransform(axis: 60, label: 'mirror · C4'),
          SpectralMappingTransform(table: {60: 72}, label: 'spectral'),
        ],
      );

      // Note 1: invert(60)=60, then table 60→72.
      // Note 2: invert(64)=56, absent from table → passes through.
      expect(chain.output.map((n) => n.pitch), [72, 56]);

      // Toggling inversion off leaves only the spectral mapping.
      chain.setActiveAt(0, false);
      // Note 1: 60 → 72. Note 2: 64 untouched.
      expect(chain.output.map((n) => n.pitch), [72, 64]);
    });

    test('voice transforms compose: route, then split per channel', () {
      // Keyboard split at C4 sends low notes to channel 1 and high notes to
      // channel 2; the splitter then layers an octave-up ghost on top of
      // every routed note. Order matters: the ghost inherits the channel the
      // router assigned.
      final chain = MidiTransformChain(
        source: _clip(const [
          MidiNote(pitch: 50, start: 0, duration: 1, velocity: 0.8),
          MidiNote(pitch: 70, start: 1, duration: 1, velocity: 0.8),
        ]),
        transforms: const [
          VoiceRoutingTransform(
            rules: [
              PitchRangeRule(minPitch: 0, maxPitch: 59, channel: 1),
              PitchRangeRule(minPitch: 60, maxPitch: 127, channel: 2),
            ],
            label: 'split @ 60',
          ),
          SplittingTransform(
            voices: [
              SplitVoice(),
              SplitVoice(pitchOffset: 12, velocityScale: 0.5),
            ],
            label: 'ghost octave',
          ),
        ],
      );

      final out = chain.output;

      expect(out.map((n) => n.pitch), [50, 62, 70, 82]);
      expect(out.map((n) => n.channel), [1, 1, 2, 2]);
      expect(out.map((n) => n.velocity), [0.8, 0.4, 0.8, 0.4]);

      // Toggling the splitter off leaves the routed originals.
      chain.setActiveAt(1, false);
      expect(chain.output.map((n) => n.pitch), [50, 70]);
      expect(chain.output.map((n) => n.channel), [1, 2]);
    });

    test('velocity-to-parameter rides the chain without changing notes', () {
      final chain = MidiTransformChain(
        source: _clip(const [
          MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.25),
          MidiNote(pitch: 64, start: 2, duration: 1, velocity: 1.0),
        ]),
        transforms: [
          const TransposeTransform(semitones: 2, label: '+2'),
          VelocityToParameterTransform(
            parameter: 'filter.cutoff',
            curve: (v) => v * 100,
            label: 'v → cutoff',
          ),
        ],
      );

      // Notes come out transposed but otherwise untouched by the mapping.
      expect(chain.output.map((n) => n.pitch), [62, 66]);

      // The control stream derives from the same notes the chain carries.
      final mapping = chain.transforms[1] as VelocityToParameterTransform;
      final events = mapping.eventsFor(chain.output);
      expect(events.map((e) => e.beat), [0, 2]);
      expect(events.map((e) => e.value), [25, 100]);
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
