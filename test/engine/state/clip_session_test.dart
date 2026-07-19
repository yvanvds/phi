import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/scene/scene_field.dart';
import 'package:phi/domain/time_domains/tempo_source_stack.dart';
import 'package:phi/engine/bridge/midi_gateway.dart';
import 'package:phi/engine/bridge/scene_agent_sink.dart';
import 'package:phi/engine/state/clip_session.dart';
import 'package:phi/engine/state/clip_session_host.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// A minimal [ClipSessionHost] that borrows only a gateway — enough to prove a
/// [ClipSession] plays entirely on its own, decoupled from [EngineMidiController].
class _StubHost implements ClipSessionHost {
  _StubHost(this.gateway);

  @override
  final MidiGateway gateway;
  @override
  final SceneField field = SceneField();
  @override
  final SceneAgentSink? agentSink = null;
  @override
  final TempoSourceStack tempoSources = TempoSourceStack();
  @override
  bool microtonal = false;
  @override
  double sessionBpm = 120;

  @override
  int? resolveOutputPort() => gateway.outputDeviceCount > 0 ? 0 : null;

  @override
  GraphEvalContext liveContext() => const GraphEvalContext.empty();
}

MidiTransformChain _twoBarChain() => MidiTransformChain(
  source: MidiClip(
    bars: 2,
    notes: const [
      MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
      MidiNote(pitch: 64, start: 2.0, duration: 0.5, velocity: 0.5),
    ],
  ),
);

void main() {
  group('ClipSession — bundle plays through a host seam (#186)', () {
    test('bundles its own chain, editor and graph from the source chain', () {
      final chain = _twoBarChain();
      final session = ClipSession(
        address: EntityAddress(kind: 'clip', segments: const ['phrase_a']),
        host: _StubHost(FakeMidiGateway()),
        chain: chain,
      );

      // The three per-clip objects are wired to the one source clip.
      expect(identical(session.chain, chain), isTrue);
      expect(identical(session.editor.clip, chain.source), isTrue);
      expect(session.graphController.graph.source, chain.source);

      session.dispose();
    });

    test('play pushes the flattened output; stop rewinds + allNotesOff', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final session = ClipSession(
          address: null,
          host: _StubHost(gateway),
          chain: _twoBarChain(),
        );

        expect(session.play(), isTrue);
        // Drive the ticker the manager would normally spin.
        async.elapse(const Duration(milliseconds: 100));
        session.advance(0.016);

        final transport = gateway.transport!;
        expect(gateway.calls, contains('open:0'));
        expect(transport.isPlaying, isTrue);
        expect(transport.loopBeats, 8);
        expect(transport.events.map((e) => e.pitch), [60, 64]);
        expect(session.playhead.value, greaterThan(0));

        // Playing again is a no-op.
        expect(session.play(), isFalse);

        expect(session.stop(), isTrue);
        expect(transport.isPlaying, isFalse);
        expect(gateway.calls, contains('allNotesOff:all'));
        expect(session.playhead.value, 0);
        // Stopping again is a no-op.
        expect(session.stop(), isFalse);

        session.dispose();
      });
    });

    test('an edit while playing re-pushes on the next advance', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final session = ClipSession(
          address: null,
          host: _StubHost(gateway),
          chain: MidiTransformChain(
            source: MidiClip(
              bars: 1,
              notes: const [
                MidiNote(pitch: 60, start: 0.0, duration: 1.0, velocity: 1.0),
              ],
            ),
            transforms: const [TransposeTransform(semitones: 7, label: '+7')],
          ),
        );

        session.play();
        async.elapse(const Duration(milliseconds: 20));
        session.advance(0.016);
        final transport = gateway.transport!;
        // Pushes the transformed output (60 → +7 → 67), not the raw source.
        expect(transport.events.map((e) => e.pitch), [67]);
        expect(transport.pushCount, 1);

        session.editor.addNote(
          const MidiNote(pitch: 58, start: 3.0, duration: 0.5, velocity: 1.0),
        );
        session.advance(0.016);
        expect(transport.pushCount, 2);
        // 58 → +7 → 65, alongside the original 67.
        expect(transport.events.map((e) => e.pitch), containsAll([67, 65]));

        session.stop();
        session.dispose();
      });
    });
  });
}
