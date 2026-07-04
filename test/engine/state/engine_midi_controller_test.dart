import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/state_machine/performance_state.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';
import 'package:phi/domain/state_machine/state_graph.dart';
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

    test('reflects clip edits made while playing on the next loop window', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        // 1.5 s = 3 beats — past notes at beats 0 and 2, before beat 4.
        async.elapse(const Duration(milliseconds: 1500));
        expect(
          gateway.calls.any((c) => c == 'noteOn:0:72:127'),
          isFalse,
          reason: 'note 72 does not exist yet',
        );

        // Author a new note at beat 5 through the *same* editor the surface
        // uses — the player reads it live, no restart.
        controller.editor.addNote(
          const MidiNote(pitch: 72, start: 5.0, duration: 0.5, velocity: 1.0),
        );

        // 3.0 s total = 6 beats — crosses the new note's onset at beat 5.
        async.elapse(const Duration(milliseconds: 1500));
        controller.stop();

        expect(gateway.calls, contains('noteOn:0:72:127'));

        controller.dispose();
      });
    });

    test('microtonal mode voices a fractional pitch as bend + rounded note', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: MidiTransformChain(
            source: MidiClip(
              name: 'micro',
              bars: 1,
              notes: const [
                // 60.25 = a quarter-of-a-semitone (25 cents) above C4.
                MidiNote(
                  pitch: 60.25,
                  start: 0.0,
                  duration: 1.0,
                  velocity: 1.0,
                ),
              ],
            ),
          ),
          gateway: gateway,
          microtonal: true,
        );

        controller.play();
        // 0.6 s = 1.2 beats — crosses the note's on (beat 0) and off (beat 1).
        async.elapse(const Duration(milliseconds: 600));
        controller.stop();

        // 25 cents / 200 (±2-semitone range) × 8192 = +1024 → 9216. The note
        // plays on its rounded semitone (60), the cents live in the bend.
        expect(gateway.calls, [
          'open:0',
          'pitchBend:0:9216',
          'noteOn:0:60:127',
          'noteOff:0:60',
          'allNotesOff:all',
        ]);

        controller.dispose();
      });
    });

    test('without microtonal mode a fractional pitch rounds, no bend', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: MidiTransformChain(
            source: MidiClip(
              name: 'micro',
              bars: 1,
              notes: const [
                MidiNote(
                  pitch: 60.25,
                  start: 0.0,
                  duration: 1.0,
                  velocity: 1.0,
                ),
              ],
            ),
          ),
          gateway: gateway, // microtonal defaults to false
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 600));
        controller.stop();

        expect(gateway.calls.any((c) => c.startsWith('pitchBend')), isFalse);
        expect(gateway.calls, contains('noteOn:0:60:127'));

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

  group('EngineMidiController — graph-mode playback (#77)', () {
    // A 1-bar clip (4 beats) with a single note at beat 0.
    MidiTransformChain oneNoteChain() => MidiTransformChain(
      source: MidiClip(
        name: 'one note',
        bars: 1,
        notes: const [
          MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
        ],
      ),
    );

    test('graph mode drives playback from the graph, not the linear chain', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: oneNoteChain(), // no chain transforms → chain output is 60
          gateway: gateway,
        );

        // Author a +7 node in the graph and switch the clip to graph mode: now
        // playback must follow the graph (67), never the linear chain (60).
        final graph = controller.graphController;
        final node = graph.addNodeAt(
          const TransposeTransform(semitones: 7, label: '+7'),
          const Offset(200, 240),
        );
        graph.connect(TransformNodeId.source, node.id);
        graph.mode = MidiClipMode.graph;

        controller.play();
        async.elapse(const Duration(milliseconds: 100));
        controller.stop();

        expect(gateway.calls, contains('noteOn:0:67:127'));
        expect(gateway.calls.any((c) => c.startsWith('noteOn:0:60')), isFalse);

        controller.dispose();
      });
    });

    test(
      'a state-guarded branch changes the emitted notes as the state flips',
      () {
        fakeAsync((async) {
          const brk = PerformanceStateId('break');
          final stateGraph = StateGraph()
            ..addState(
              PerformanceState(
                id: brk,
                name: 'break',
                voice: 3,
                position: Offset.zero,
              ),
            );
          final gateway = FakeMidiGateway();
          final controller = EngineMidiController(
            chain: oneNoteChain(),
            gateway: gateway,
            stateGraph: stateGraph,
          );

          // Baseline spine: source → +0 (unconditional), always terminal → 60.
          // Branch: source → +12 guarded by `break`, a second terminal that
          // only carries notes while `break` is live → adds 72 to the union.
          final graph = controller.graphController;
          final base = graph.addNodeAt(
            const TransposeTransform(semitones: 0, label: 'base'),
            const Offset(200, 200),
          );
          graph.connect(TransformNodeId.source, base.id);
          final branch = graph.addNodeAt(
            const TransposeTransform(semitones: 12, label: 'branch · +12'),
            const Offset(200, 360),
          );
          graph.connect(
            TransformNodeId.source,
            branch.id,
            condition: const StateMatchCondition(brk),
          );
          graph.mode = MidiClipMode.graph;

          // No state live: the branch is closed → only 60 sounds.
          controller.play();
          async.elapse(const Duration(milliseconds: 100));
          expect(gateway.calls, contains('noteOn:0:60:127'));
          expect(
            gateway.calls.any((c) => c.startsWith('noteOn:0:72')),
            isFalse,
          );

          // Go live on `break` → the branch opens; on the next loop the beat-0
          // note fans out to both terminals, so 72 joins 60 in the output.
          stateGraph.setActive(brk);
          async.elapse(
            const Duration(milliseconds: 2000),
          ); // wrap the 4-beat bar
          controller.stop();

          expect(gateway.calls, contains('noteOn:0:72:127'));

          controller.dispose();
        });
      },
    );
  });
}
