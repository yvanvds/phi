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
import 'package:phi/engine/bridge/transport_note.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';
import '../test_doubles/fake_midi_transport.dart';

/// A 2-bar clip (8 beats) with three notes at known positions, no overlap.
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

/// The transport the controller minted, or a failure if it never played.
FakeMidiTransport transportOf(FakeMidiGateway gateway) {
  final t = gateway.transport;
  expect(t, isNotNull, reason: 'the controller should have minted a transport');
  return t!;
}

/// A compact `(channel, pitch, start, duration, velocity)` view of the pushed
/// events, for order-sensitive assertions.
List<(int, int, double, double, double)> shapeOf(List<TransportNote> events) =>
    [
      for (final e in events)
        (e.channel, e.pitch, e.startBeat, e.durationBeats, e.velocity),
    ];

void main() {
  group('EngineMidiController — push contract (#101)', () {
    test('play pushes the whole clip as a flattened event list + loop', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 100));

        // The port opened and a transport was minted, then the events pushed.
        expect(gateway.calls, contains('open:0'));
        final transport = transportOf(gateway);
        expect(transport.isPlaying, isTrue);
        expect(transport.loopBeats, 8);
        expect(shapeOf(transport.events), [
          (0, 60, 0.0, 1.0, 1.0),
          (0, 64, 2.0, 0.5, 0.5),
          (0, 67, 4.0, 2.0, 0.8),
        ]);

        controller.stop();
        controller.dispose();
      });
    });

    test('the whole clip is pushed once — the engine owns looping', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        // Elapse well past the 8-beat loop. A static clip must not re-push —
        // the engine loops the single pushed buffer, Dart doesn't re-dispatch.
        async.elapse(const Duration(milliseconds: 5000));
        controller.stop();

        final transport = transportOf(gateway);
        expect(transport.pushCount, 1);
        expect(transport.loopBeats, 8);
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

    test('stop stops the transport and sends allNotesOff', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 400));
        final transport = transportOf(gateway);
        controller.stop();

        expect(transport.isPlaying, isFalse);
        expect(transport.calls, contains('stop'));
        expect(gateway.calls, contains('allNotesOff:all'));

        controller.dispose();
      });
    });

    test('pushes the transformed output, not the raw source', () {
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

        final transport = transportOf(gateway);
        // Transposed +7: pitch 60 pushes as 67, never the raw 60.
        expect(transport.events.map((e) => e.pitch), [67]);

        controller.dispose();
      });
    });

    test('re-pushes on a clip edit made while playing', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 100));
        final transport = transportOf(gateway);
        expect(transport.pushCount, 1);
        expect(transport.events.any((e) => e.pitch == 72), isFalse);

        // Author a new note through the *same* editor the surface uses.
        controller.editor.addNote(
          const MidiNote(pitch: 72, start: 5.0, duration: 0.5, velocity: 1.0),
        );
        // One tick later the memoised output changed instance → a re-push.
        async.elapse(const Duration(milliseconds: 20));

        expect(transport.pushCount, 2);
        expect(transport.events.any((e) => e.pitch == 72), isTrue);
        controller.stop();
        controller.dispose();
      });
    });

    test('microtonal mode carries the leftover cents as bend event data', () {
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
        async.elapse(const Duration(milliseconds: 100));
        controller.stop();

        final event = transportOf(gateway).events.single;
        // Plays on the rounded semitone (60); 25 cents / 200 (±2-semitone
        // range) = 0.125 of full deflection, carried as normalised bend.
        expect(event.pitch, 60);
        expect(event.pitchBend, closeTo(0.125, 1e-9));

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
        async.elapse(const Duration(milliseconds: 100));
        controller.stop();

        final event = transportOf(gateway).events.single;
        expect(event.pitch, 60);
        expect(event.pitchBend, 0.0);

        controller.dispose();
      });
    });

    test('toggling microtonal while playing re-pushes with the new bend', () {
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
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 40));
        final transport = transportOf(gateway);
        expect(transport.events.single.pitchBend, 0.0);
        final pushesBefore = transport.pushCount;

        controller.microtonal = true;
        expect(transport.pushCount, pushesBefore + 1);
        expect(transport.events.single.pitchBend, closeTo(0.125, 1e-9));

        controller.stop();
        controller.dispose();
      });
    });

    test('bpm setter ignores non-positive values and ramps the clock', () {
      fakeAsync((async) {
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

        controller.play();
        async.elapse(const Duration(milliseconds: 20));
        controller.bpm = 100;
        expect(transportOf(gateway).tempo, 100);

        controller.stop();
        controller.dispose();
      });
    });

    test('pushes even when no output device is present', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway()..deviceNames = const [];
        final controller = EngineMidiController(
          chain: _twoBarChain(),
          gateway: gateway,
        );

        controller.play();
        async.elapse(const Duration(milliseconds: 100));
        controller.stop();

        // No port opened, but the transport still received the clip — a real
        // gateway would simply have no external sink to route to.
        expect(gateway.calls, isNot(contains('open:0')));
        expect(transportOf(gateway).events, isNotEmpty);

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

    test('graph mode pushes the graph output, not the linear chain', () {
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

        expect(transportOf(gateway).events.map((e) => e.pitch), [67]);

        controller.dispose();
      });
    });

    test('a state-guarded branch re-pushes as the state flips', () {
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
        // Branch: source → +12 guarded by `break`, a second terminal that only
        // carries notes while `break` is live → adds 72 to the union.
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

        // No state live: the branch is closed → only 60 is pushed.
        controller.play();
        async.elapse(const Duration(milliseconds: 40));
        final transport = transportOf(gateway);
        expect(transport.events.map((e) => e.pitch), [60]);

        // Go live on `break` → the branch opens; the next tick re-evaluates,
        // sees a fresh output instance, and re-pushes 72 alongside 60.
        stateGraph.setActive(brk);
        async.elapse(const Duration(milliseconds: 40));
        controller.stop();

        expect(transport.events.map((e) => e.pitch), containsAll([60, 72]));

        controller.dispose();
      });
    });
  });
}
