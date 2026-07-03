import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
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
