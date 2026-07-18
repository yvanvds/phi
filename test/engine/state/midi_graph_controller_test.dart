import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_clip_mode.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/state_machine/performance_state_id.dart';
import 'package:phi/engine/state/midi_graph_controller.dart';

void main() {
  MidiTransformChain chainWith(List<int> transposes) => MidiTransformChain(
    source: MidiClip(
      name: 't',
      bars: 1,
      notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
    ),
    transforms: [
      for (final st in transposes)
        TransposeTransform(semitones: st, label: '+$st'),
    ],
  );

  test('seededFrom mirrors the chain output note-for-note', () {
    final chain = chainWith([5, 2]);
    final controller = MidiGraphController.seededFrom(chain);

    // source → +5 → +2, all unconditional: 60 → 67, matching the chain.
    expect(controller.graph.evaluate().single.pitch, chain.output.single.pitch);
    expect(controller.graph.evaluate().single.pitch, 67);
    // Two transform nodes, laid out to the right of the source.
    expect(controller.graph.nodes, hasLength(2));
    expect(controller.positionOf(TransformNodeId.source).dx, lessThan(200));
    expect(
      controller.positionOf(controller.graph.nodes.last.id).dx,
      greaterThan(controller.positionOf(controller.graph.nodes.first.id).dx),
    );

    controller.dispose();
    chain.dispose();
  });

  test(
    'addNodeAt registers a grid-snapped position for a disconnected node',
    () {
      final chain = chainWith(const []);
      final controller = MidiGraphController.seededFrom(chain);

      final node = controller.addNodeAt(
        const TransposeTransform(semitones: 12, label: '+12'),
        const Offset(203, 197),
      );

      expect(controller.graph.nodes, contains(node));
      expect(controller.graph.edges, isEmpty); // starts unwired
      expect(controller.positionOf(node.id), const Offset(208, 192)); // snapped

      controller.dispose();
      chain.dispose();
    },
  );

  test('moveNode snaps to the grid and notifies', () {
    final chain = chainWith(const []);
    final controller = MidiGraphController.seededFrom(chain);
    final node = controller.addNodeAt(
      const TransposeTransform(semitones: 1, label: '+1'),
      const Offset(96, 96),
    );

    var notified = 0;
    controller.addListener(() => notified++);
    controller.moveNode(node.id, const Offset(10, 10));

    expect(controller.positionOf(node.id), const Offset(112, 112));
    expect(notified, 1);

    controller.dispose();
    chain.dispose();
  });

  test('connect rejects a cycle and reports it through the bool', () {
    final chain = chainWith(const []);
    final controller = MidiGraphController.seededFrom(chain);
    final a = controller.addNodeAt(
      const TransposeTransform(semitones: 1, label: 'a'),
      const Offset(0, 0),
    );
    final b = controller.addNodeAt(
      const TransposeTransform(semitones: 1, label: 'b'),
      const Offset(200, 0),
    );

    expect(controller.connect(a.id, b.id), isTrue);
    expect(controller.connect(b.id, a.id), isFalse); // would close a cycle
    expect(controller.connect(a.id, b.id), isFalse); // duplicate pair

    controller.dispose();
    chain.dispose();
  });

  test('setEdgeCondition swaps the guard on an existing edge', () {
    final chain = chainWith([3]);
    final controller = MidiGraphController.seededFrom(chain);
    final node = controller.graph.nodes.single;
    const stateId = PerformanceStateId('s1');

    final ok = controller.setEdgeCondition(
      TransformNodeId.source,
      node.id,
      const StateMatchCondition(stateId),
    );

    expect(ok, isTrue);
    final edge = controller.graph.edges.single;
    expect(edge.condition, const StateMatchCondition(stateId));
    // With no state live the guard is closed, so the node passes through and
    // the source notes reach the (now unreachable) output unchanged.
    expect(controller.graph.evaluate().single.pitch, 60);

    controller.dispose();
    chain.dispose();
  });

  test('mode defaults to chain and notifies only on a real change', () {
    final chain = chainWith(const []);
    final controller = MidiGraphController.seededFrom(chain);
    var notified = 0;
    controller.addListener(() => notified++);

    expect(controller.mode, MidiClipMode.chain);
    controller.mode = MidiClipMode.graph;
    expect(controller.mode, MidiClipMode.graph);
    controller.mode = MidiClipMode.graph; // no-op, same value
    expect(notified, 1);

    controller.dispose();
    chain.dispose();
  });

  test('loadFromChain re-seeds the graph from the current chain', () {
    // Seed the controller off an empty chain, then grow the chain and reload:
    // the graph must reflect the *current* chain, not the one seeded at build.
    final chain = chainWith(const []);
    final controller = MidiGraphController.seededFrom(chain);
    expect(controller.graph.nodes, isEmpty);

    chain
      ..add(const TransposeTransform(semitones: 5, label: '+5'))
      ..add(const TransposeTransform(semitones: 2, label: '+2'));

    var notified = 0;
    controller.addListener(() => notified++);
    controller.loadFromChain(chain);

    // A linear spine matching the chain: 60 → +5 → +2 → 67.
    expect(controller.graph.nodes, hasLength(2));
    expect(controller.graph.isLinear, isTrue);
    expect(controller.graph.evaluate().single.pitch, 67);
    expect(controller.positionOf(TransformNodeId.source).dx, lessThan(200));
    expect(notified, greaterThan(0));

    controller.dispose();
    chain.dispose();
  });

  test('loadFromChain replaces a previously branched graph', () {
    final chain = chainWith([5]);
    final controller = MidiGraphController.seededFrom(chain);
    // Author an extra branch so the graph is no longer linear.
    final branch = controller.addNodeAt(
      const TransposeTransform(semitones: 12, label: '+12'),
      const Offset(200, 360),
    );
    controller.connect(TransformNodeId.source, branch.id);
    expect(controller.graph.isLinear, isFalse);

    controller.loadFromChain(chain);

    // Back to the chain's single-node linear spine — the branch is gone.
    expect(controller.graph.nodes, hasLength(1));
    expect(controller.graph.isLinear, isTrue);

    controller.dispose();
    chain.dispose();
  });

  test('loadFromGraph copies a branched graph over the live source', () {
    final chain = chainWith(const []);
    final controller = MidiGraphController.seededFrom(chain);

    // A branched source graph (as a decoded document would arrive): source → +7
    // unconditional, and source → +12 guarded by a state that is not live.
    final source = MidiTransformGraph(
      source: MidiClip(
        name: 's',
        bars: 1,
        notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 1)],
      ),
    );
    final a = source.addNode(
      const TransposeTransform(semitones: 7, label: '+7'),
    );
    final b = source.addNode(
      const TransposeTransform(semitones: 12, label: '+12'),
    );
    source.connect(TransformNodeId.source, a.id);
    source.connect(
      TransformNodeId.source,
      b.id,
      condition: const StateMatchCondition(PerformanceStateId('x')),
    );

    var notified = 0;
    controller.addListener(() => notified++);
    controller.loadFromGraph(source);

    // Nodes and edges copied, structure preserved, and notified.
    expect(controller.graph.nodes, hasLength(2));
    expect(controller.graph.edges, hasLength(2));
    expect(
      controller.graph.edges.any((e) => e.condition is StateMatchCondition),
      isTrue,
    );
    expect(notified, greaterThan(0));
    // Fresh ids are minted — the source's node ids are not reused.
    expect(controller.graph.nodes.map((n) => n.id), isNot(contains(a.id)));
    // The live graph evaluates over the live source clip (pitch 60); with no
    // state live the +12 branch is closed, so only +7 reaches the output.
    expect(controller.graph.evaluate().map((n) => n.pitch), [67]);
    // Every copied node has a laid-out position (right of the source).
    for (final node in controller.graph.nodes) {
      expect(
        controller.positionOf(node.id).dx,
        greaterThan(controller.positionOf(TransformNodeId.source).dx),
      );
    }

    source.dispose();
    controller.dispose();
    chain.dispose();
  });

  test('begin/endCableDrag toggles the drag source and notifies', () {
    final chain = chainWith(const []);
    final controller = MidiGraphController.seededFrom(chain);
    var notified = 0;
    controller.addListener(() => notified++);

    expect(controller.dragSourceId, isNull);
    controller.beginCableDrag(TransformNodeId.source);
    expect(controller.dragSourceId, TransformNodeId.source);
    controller.endCableDrag();
    expect(controller.dragSourceId, isNull);
    expect(notified, 2);

    controller.dispose();
    chain.dispose();
  });
}
