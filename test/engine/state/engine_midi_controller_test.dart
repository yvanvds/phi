import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// A 2-bar clip (8 beats) with three notes at known positions, no overlap.
/// Velocities pick round-trip-friendly values: 1.0→127, 0.5→64, 0.8→102.
MidiTransformChain _twoBarChain() => MidiTransformChain(
  source: MidiClip(
    name: 'two bars',
    bars: 2,
    notes: const [
      MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
      MidiNote(pitch: 64, start: 2.0, duration: 0.5, velocity: 0.5),
      MidiNote(pitch: 67, start: 4.0, duration: 2.0, velocity: 0.8),
    ],
  ),
);

void main() {
  group('EngineMidiController', () {
    test('plays a 2-bar clip as the expected note sequence', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        // 3.9 s @ 120 BPM = 7.8 beats — crosses every event in the first
        // loop (last is the C note-off at beat 6) but stays short of the
        // loop wrap at beat 8, so nothing re-triggers.
        async.elapse(const Duration(milliseconds: 3900));
        controller.stop();

        expect(gateway.calls, [
          'open:0',
          'noteOn:0:60:127',
          'noteOff:0:60',
          'noteOn:0:64:64',
          'noteOff:0:64',
          'noteOn:0:67:102',
          'noteOff:0:67',
          'allNotesOff:all',
        ]);

        controller.dispose();
      });
    });

    test('advances the playhead while playing and rewinds on stop', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        expect(controller.playhead.value, 0);
        controller.play();
        async.elapse(const Duration(seconds: 1)); // 2 beats in
        expect(controller.isPlaying, isTrue);
        expect(controller.playhead.value, greaterThan(0));

        controller.stop();
        expect(controller.isPlaying, isFalse);
        expect(controller.playhead.value, 0);

        controller.dispose();
      });
    });

    test('loops: the clip restarts after totalBeats', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        // 4.6 s = 9.2 beats — past the wrap at 8, so note 60 fires twice.
        async.elapse(const Duration(milliseconds: 4600));
        controller.stop();

        final firstNoteOns = gateway.calls
            .where((c) => c == 'noteOn:0:60:127')
            .length;
        expect(firstNoteOns, 2);

        controller.dispose();
      });
    });

    test('stop sends allNotesOff so a note held at stop is not left hung', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        // 0.4 s = 0.8 beats — inside note 60 (spans beats 0..1), so its
        // note-off has not been scheduled yet.
        async.elapse(const Duration(milliseconds: 400));
        controller.stop();

        expect(gateway.calls, ['open:0', 'noteOn:0:60:127', 'allNotesOff:all']);

        controller.dispose();
      });
    });

    test('reads the transformed output, not the raw source', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: MidiTransformChain(
            source: MidiClip(
              name: 'one note',
              bars: 1,
              notes: const [
                MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
              ],
            ),
            transforms: const [TransposeTransform(semitones: 7, label: '+7')],
          ),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 100));
        controller.stop();

        // Transposed +7: pitch 60 plays as 67, never the raw 60.
        expect(gateway.calls, contains('noteOn:0:67:127'));
        expect(gateway.calls.any((c) => c.startsWith('noteOn:0:60')), isFalse);

        controller.dispose();
      });
    });

    test('bpm setter ignores non-positive values', () {
      final gateway = FakeMidiGateway();
      final controller = EngineMidiController(
        chain: _twoBarChain(),
        gateway: gateway,
        bpm: 90,
      );
      controller.bpm = 0;
      expect(controller.bpm, 90);
      controller.bpm = -10;
      expect(controller.bpm, 90);
      controller.bpm = 140;
      expect(controller.bpm, 140);
      controller.dispose();
    });

    test('does not open a port when no output device is present', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway()..deviceNames = const [];
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 100));
        controller.stop();

        expect(gateway.calls, isNot(contains('open:0')));
        // Note dispatch still runs (the gateway no-ops), playhead still moves.
        expect(gateway.calls, contains('noteOn:0:60:127'));

        controller.dispose();
      });
    });
  });
}
