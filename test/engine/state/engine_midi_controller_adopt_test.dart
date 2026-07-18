import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/store/clip_document.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/engine/state/engine_midi_controller.dart';

import '../test_doubles/fake_midi_gateway.dart';

/// `EngineMidiController.adoptDocument` (issue #139) — the engine half of
/// restoring a saved clip on project open. It must replay a loaded
/// [ClipDocument] into the *live* clip objects in place, so surfaces already
/// bound to the chain / editor / graph controller follow without re-wiring.
MidiTransformChain _seedChain() => MidiTransformChain(
  source: MidiClip(
    name: 'seed',
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
  ),
  transforms: const [TransposeTransform(semitones: 1, label: 'seed +1')],
);

void main() {
  test('adoptDocument replaces source, chain and editor in place', () {
    final gateway = FakeMidiGateway();
    final controller = EngineMidiController(
      chain: _seedChain(),
      gateway: gateway,
    );
    // Capture the live instances to prove identity survives the adoption.
    final liveChain = controller.chain;
    final liveEditor = controller.editor;
    final liveSource = controller.chain.source;

    // Author an edit so we can prove the adopt resets the undo history.
    controller.editor.addNote(
      const MidiNote(pitch: 64, start: 0, duration: 1, velocity: 1),
    );
    expect(controller.editor.canUndo, isTrue);

    final document = ClipDocument(
      source: MidiClip(
        name: 'loaded',
        bars: 2,
        notes: const [
          MidiNote(pitch: 72, start: 0, duration: 0.5, velocity: 0.7),
          MidiNote(pitch: 74, start: 1, duration: 0.5, velocity: 0.6),
        ],
      ),
      chain: const [TransposeTransform(semitones: 5, label: 'loaded +5')],
    );

    controller.adoptDocument(document);

    // Same instances, new contents — nothing was recreated.
    expect(identical(controller.chain, liveChain), isTrue);
    expect(identical(controller.editor, liveEditor), isTrue);
    expect(identical(controller.chain.source, liveSource), isTrue);
    expect(controller.chain.source.name, 'loaded');
    expect(controller.chain.source.bars, 2);
    expect(controller.chain.source.notes.map((n) => n.pitch), [72, 74]);
    expect(controller.chain.transforms.single.label, 'loaded +5');
    // Output reflects the adopted source + chain: 72 → +5 → 77, 74 → 79.
    expect(controller.chain.output.map((n) => n.pitch), [77, 79]);
    // The stale undo history was dropped.
    expect(controller.editor.canUndo, isFalse);
    // A chain-only document leaves the clip in chain mode with the graph
    // re-seeded from the fresh chain (so a later convert-to-graph is current).
    expect(controller.graphController.mode, MidiClipMode.chain);
    expect(controller.graphController.graph.nodes, hasLength(1));

    controller.dispose();
  });

  test('adoptDocument restores a graph-mode clip', () {
    final gateway = FakeMidiGateway();
    final controller = EngineMidiController(
      chain: _seedChain(),
      gateway: gateway,
    );

    final loadedSource = MidiClip(
      name: 'g',
      bars: 1,
      notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
    );
    final graph = MidiTransformGraph(source: loadedSource);
    final node = graph.addNode(
      const TransposeTransform(semitones: 7, label: '+7'),
    );
    graph.connect(TransformNodeId.source, node.id);

    controller.adoptDocument(
      ClipDocument(
        source: loadedSource,
        mode: MidiClipMode.graph,
        graph: graph,
      ),
    );

    // The clip is in graph mode with the branch restored, evaluating over the
    // adopted live source: 60 → +7 → 67.
    expect(controller.graphController.mode, MidiClipMode.graph);
    expect(controller.graphController.graph.nodes, hasLength(1));
    expect(controller.graphController.graph.evaluate().single.pitch, 67);

    graph.dispose();
    controller.dispose();
  });
}
