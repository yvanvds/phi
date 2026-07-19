import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// The default boot session's seed chain — a single note, one transpose chip.
MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
  transforms: const [TransposeTransform(semitones: 1, label: 'seed +1')],
);

EntityAddress _clip(String name) =>
    EntityAddress(kind: 'clip', segments: [name]);

/// A chain-only document for [pitch], transposed by [semitones].
ClipDocument _chainDoc(double pitch, {int semitones = 5}) => ClipDocument(
  source: MidiClip(
    bars: 2,
    notes: [MidiNote(pitch: pitch, start: 0, duration: 1, velocity: 1)],
  ),
  chain: [TransposeTransform(semitones: semitones, label: '+$semitones')],
);

void main() {
  group('EngineMidiController — session manager (#186)', () {
    test('opens a clip entity as the edited session; getters follow it', () {
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: FakeMidiGateway(),
      );
      final bootChain = controller.chain;
      final bootEditor = controller.editor;

      final session = controller.openSession(_clip('phrase_b'), _chainDoc(72));

      // The edited session is the freshly opened one, and every delegating
      // getter now reads it — the surface would bind straight through.
      expect(identical(controller.editedSession, session), isTrue);
      expect(identical(controller.chain, session.chain), isTrue);
      expect(identical(controller.editor, session.editor), isTrue);
      expect(
        identical(controller.graphController, session.graphController),
        isTrue,
      );
      expect(controller.chain.source.notes.map((n) => n.pitch), [72]);
      // 72 → +5 → 77.
      expect(controller.chain.output.map((n) => n.pitch), [77]);

      // The boot session's objects are a different bundle — not mutated in place.
      expect(identical(controller.chain, bootChain), isFalse);
      expect(identical(controller.editor, bootEditor), isFalse);

      controller.dispose();
    });

    test('reopening the same address reuses its session', () {
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: FakeMidiGateway(),
      );
      final addr = _clip('phrase_b');

      final first = controller.openSession(addr, _chainDoc(72));
      // Switch away, then back — the second call must not mint a new session.
      controller.openSession(_clip('phrase_c'), _chainDoc(60));
      final second = controller.openSession(addr, _chainDoc(72));

      expect(identical(first, second), isTrue);
      expect(identical(controller.editedSession, first), isTrue);
      expect(controller.sessionFor(addr), same(first));

      controller.dispose();
    });

    test('swapping the edited session leaks neither the transport nor the '
        'previous session', () {
      fakeAsync((async) {
        final gateway = FakeMidiGateway();
        final controller = EngineMidiController(
          chain: _seedChain(),
          gateway: gateway,
        );

        // Play the boot session, then open a different clip as the edited one.
        controller.play();
        async.elapse(const Duration(milliseconds: 20));
        final bootTransport = gateway.transport!;
        expect(bootTransport.isPlaying, isTrue);

        controller.openSession(_clip('phrase_b'), _chainDoc(72));

        // Swapping the editor does NOT tear the boot session down: its transport
        // is retained and keeps running (it is a separate playing session now —
        // the concurrency the next issue turns on).
        expect(bootTransport.isPlaying, isTrue);
        expect(bootTransport.calls, isNot(contains('dispose')));

        // Disposing the manager releases every session's transport, not just the
        // edited one — nothing is orphaned.
        controller.dispose();
        expect(bootTransport.calls, contains('stop'));
        expect(bootTransport.calls, contains('dispose'));
      });
    });

    test('ensureSession opens a session without making it the edited one', () {
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: FakeMidiGateway(),
      );
      final boot = controller.editedSession;

      final session = controller.ensureSession(
        _clip('phrase_b'),
        _chainDoc(72),
      );

      // A session now exists for the address, reachable via sessionFor…
      expect(
        identical(controller.sessionFor(_clip('phrase_b')), session),
        isTrue,
      );
      // …but the edited session is untouched — the row can play without swapping
      // the clip open in the editor (issue #188).
      expect(identical(controller.editedSession, boot), isTrue);

      // A second ensure reuses the same session (never re-adopts over edits).
      final again = controller.ensureSession(_clip('phrase_b'), _chainDoc(0));
      expect(identical(again, session), isTrue);

      controller.dispose();
    });

    test('opens a graph-mode document in graph mode', () {
      final controller = EngineMidiController(
        chain: _seedChain(),
        gateway: FakeMidiGateway(),
      );

      final source = MidiClip(
        bars: 1,
        notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
      );
      final graph = MidiTransformGraph(source: source);
      final node = graph.addNode(
        const TransposeTransform(semitones: 7, label: '+7'),
      );
      graph.connect(TransformNodeId.source, node.id);

      final session = controller.openSession(
        _clip('branchy'),
        ClipDocument(source: source, mode: MidiClipMode.graph, graph: graph),
      );

      expect(session.graphController.mode, MidiClipMode.graph);
      // The branch is copied onto the session's own graph over its live source:
      // 60 → +7 → 67.
      expect(session.graphController.graph.evaluate().single.pitch, 67);

      graph.dispose();
      controller.dispose();
    });
  });
}
