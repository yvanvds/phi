import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/runtime_variable_condition.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/midi_transform_chain.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';

MidiClip _clip(List<int> pitches) => MidiClip(
  bars: 1,
  notes: [
    for (final p in pitches)
      MidiNote(pitch: p.toDouble(), start: 0, duration: 1, velocity: 1),
  ],
);

TransposeTransform _t(int semis, {bool active = true}) =>
    TransposeTransform(semitones: semis, label: '+$semis', active: active);

void main() {
  group('MidiTransformGraph — linear equivalence', () {
    test('linear graph evaluates identically to the equivalent chain', () {
      const transforms = [
        TransposeTransform(semitones: 2, label: '+2'),
        TransposeTransform(semitones: 3, label: '+3'),
      ];
      final chain = MidiTransformChain(
        source: _clip([60]),
        transforms: transforms,
      );
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: transforms,
      );

      expect(
        graph.evaluate().map((n) => n.pitch),
        chain.output.map((n) => n.pitch),
      );
      expect(graph.evaluate().single.pitch, 65);
    });

    test('an inactive node passes its input through unchanged', () {
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: [_t(2), _t(5, active: false)],
      );
      // +2 applies, +5 is inactive → 62.
      expect(graph.evaluate().single.pitch, 62);
    });

    test('an empty graph returns the source notes unchanged', () {
      final graph = MidiTransformGraph(source: _clip([60, 64]));
      expect(graph.evaluate().map((n) => n.pitch), [60, 64]);
    });
  });

  group('MidiTransformGraph — branching', () {
    test('fan-out broadcasts a node output down every open branch', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(10));
      final c = graph.addNode(_t(20));
      graph.connect(TransformNodeId.source, a.id);
      graph.connect(a.id, b.id);
      graph.connect(a.id, c.id);

      // A: 60→61, broadcast to B (→71) and C (→81); both terminal.
      expect(graph.evaluate().map((n) => n.pitch), [71, 81]);
    });

    test('fan-in merges every open incoming branch', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(2));
      final c = graph.addNode(_t(10));
      graph.connect(TransformNodeId.source, a.id);
      graph.connect(TransformNodeId.source, b.id);
      graph.connect(a.id, c.id);
      graph.connect(b.id, c.id);

      // C receives A(61) and B(62), merges → [61,62], then +10 → [71,72].
      expect(graph.evaluate().map((n) => n.pitch), [71, 72]);
    });
  });

  group('MidiTransformGraph — conditional edges', () {
    final s1 = EntityAddress.parse('state.s1');
    final s2 = EntityAddress.parse('state.s2');

    MidiTransformGraph buildStateBranch() {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(10));
      final c = graph.addNode(_t(20));
      graph.connect(TransformNodeId.source, a.id);
      graph.connect(a.id, b.id, condition: StateMatchCondition(s1));
      graph.connect(a.id, c.id, condition: StateMatchCondition(s2));
      return graph;
    }

    test('the live state selects which branch fires', () {
      final graph = buildStateBranch();

      expect(
        graph.evaluate(GraphEvalContext(activeState: s1)).map((n) => n.pitch),
        [71],
      );
      expect(
        graph.evaluate(GraphEvalContext(activeState: s2)).map((n) => n.pitch),
        [81],
      );
    });

    test('with no branch open the guarding node itself is the terminal', () {
      final graph = buildStateBranch();
      // Neither state live → A has no open outgoing edge → A is terminal.
      expect(graph.evaluate().map((n) => n.pitch), [61]);
    });

    test('a runtime variable opens the matching branch', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(10));
      graph.connect(TransformNodeId.source, a.id);
      graph.connect(
        a.id,
        b.id,
        condition: const RuntimeVariableCondition(
          name: 'mode',
          expected: 'lead',
        ),
      );

      expect(
        graph
            .evaluate(const GraphEvalContext(variables: {'mode': 'lead'}))
            .map((n) => n.pitch),
        [71],
      );
      // Wrong value → branch closed → A terminal.
      expect(
        graph
            .evaluate(const GraphEvalContext(variables: {'mode': 'pad'}))
            .map((n) => n.pitch),
        [61],
      );
    });
  });

  group('MidiTransformGraph — cycle detection', () {
    test('connect rejects an edge that would close a cycle', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(1));
      expect(graph.connect(a.id, b.id), isTrue);
      // b → a would form a→b→a.
      expect(graph.connect(b.id, a.id), isFalse);
      expect(graph.edges.length, 1);
      expect(graph.hasCycle, isFalse);
      expect(graph.topologicalOrder(), isNotNull);
    });

    test('connect rejects a longer back-edge', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(1));
      final c = graph.addNode(_t(1));
      graph.connect(a.id, b.id);
      graph.connect(b.id, c.id);
      // c → a closes a→b→c→a.
      expect(graph.connect(c.id, a.id), isFalse);
    });

    test('topologicalOrder places predecessors before successors', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(1));
      final c = graph.addNode(_t(1));
      graph.connect(a.id, b.id);
      graph.connect(b.id, c.id);
      final order = graph.topologicalOrder()!;
      expect(order.indexOf(a.id), lessThan(order.indexOf(b.id)));
      expect(order.indexOf(b.id), lessThan(order.indexOf(c.id)));
    });
  });

  group('MidiTransformGraph — connect validation', () {
    test('rejects an edge into the source sentinel', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      expect(graph.connect(a.id, TransformNodeId.source), isFalse);
    });

    test('rejects an edge touching an unknown node', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      expect(graph.connect(a.id, const TransformNodeId('ghost')), isFalse);
      expect(graph.connect(const TransformNodeId('ghost'), a.id), isFalse);
    });

    test('rejects a duplicate (from, to) pair regardless of condition', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      graph.connect(TransformNodeId.source, a.id);
      expect(
        graph.connect(
          TransformNodeId.source,
          a.id,
          condition: StateMatchCondition(EntityAddress.parse('state.x')),
        ),
        isFalse,
      );
      expect(graph.edges.length, 1);
    });
  });

  group('MidiTransformGraph — mutation + notification', () {
    test('addNode / connect / removeNode / disconnect notify and bump', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      var notifications = 0;
      graph.addListener(() => notifications++);

      final a = graph.addNode(_t(1));
      expect(notifications, 1);
      expect(graph.version, 1);

      final b = graph.addNode(_t(2));
      graph.connect(a.id, b.id);
      expect(notifications, 3);

      graph.disconnect(a.id, b.id);
      expect(notifications, 4);
      expect(graph.edges, isEmpty);

      graph.removeNode(a.id);
      expect(notifications, 5);
      expect(graph.nodes.length, 1);
    });

    test('removeNode also drops edges touching it', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(1));
      graph.connect(TransformNodeId.source, a.id);
      graph.connect(a.id, b.id);
      graph.removeNode(a.id);
      expect(graph.edges, isEmpty);
    });

    test('setActive toggles pass-through and is idempotent', () {
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: [_t(5)],
      );
      final id = graph.nodes.single.id;
      expect(graph.evaluate().single.pitch, 65);

      var notifications = 0;
      graph.addListener(() => notifications++);

      graph.setActive(id, false);
      expect(notifications, 1);
      expect(graph.evaluate().single.pitch, 60);

      graph.setActive(id, false); // already inactive
      expect(notifications, 1);
    });

    test('disconnect of a missing edge does not notify', () {
      final graph = MidiTransformGraph(source: _clip([60]));
      final a = graph.addNode(_t(1));
      final b = graph.addNode(_t(1));
      var notifications = 0;
      graph.addListener(() => notifications++);
      graph.disconnect(a.id, b.id);
      expect(notifications, 0);
    });
  });

  group('MidiTransformGraph — evaluate memoisation (#56/#77)', () {
    test('repeated calls with the same context return the cached instance', () {
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: const [TransposeTransform(semitones: 5, label: '+5')],
      );

      final first = graph.evaluate();
      expect(identical(graph.evaluate(), first), isTrue);
      expect(first.single.pitch, 65);
    });

    test('a structural mutation invalidates the cache', () {
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: const [TransposeTransform(semitones: 5, label: '+5')],
      );
      final first = graph.evaluate();

      final node = graph.addNode(_t(2));
      graph.connect(graph.nodes.first.id, node.id);

      final second = graph.evaluate();
      expect(identical(second, first), isFalse);
      expect(second.single.pitch, 67); // +5 then +2
    });

    test('a source-clip edit (touch) invalidates the cache', () {
      final source = _clip([60]);
      final graph = MidiTransformGraph.linear(
        source: source,
        transforms: const [TransposeTransform(semitones: 5, label: '+5')],
      );
      final first = graph.evaluate();

      source.touch(); // the source clip changed underneath the graph
      expect(identical(graph.evaluate(), first), isFalse);
    });

    test('a changed context recomputes; re-using it re-hits the cache', () {
      final s1 = EntityAddress.parse('state.s1');
      final graph = MidiTransformGraph(source: _clip([60]));
      final node = graph.addNode(_t(5));
      // The only edge is guarded by `s1`, so under the empty context the node
      // is unreachable and the source passes through unchanged.
      graph.connect(
        TransformNodeId.source,
        node.id,
        condition: StateMatchCondition(s1),
      );

      final dark = graph.evaluate(const GraphEvalContext.empty());
      expect(dark.single.pitch, 60);

      final live = GraphEvalContext(activeState: s1);
      final lit = graph.evaluate(live);
      expect(identical(lit, dark), isFalse); // context differs → recompute
      expect(lit.single.pitch, 65); // edge open → +5 applied

      // Same context again re-hits the single slot.
      expect(identical(graph.evaluate(live), lit), isTrue);
    });
  });

  group('MidiTransformGraph — linear-chain conversion (#77)', () {
    test('clear drops every node and edge and notifies once', () {
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: const [
          TransposeTransform(semitones: 5, label: '+5'),
          TransposeTransform(semitones: 2, label: '+2'),
        ],
      );
      var notifications = 0;
      graph.addListener(() => notifications++);

      graph.clear();
      expect(graph.nodes, isEmpty);
      expect(graph.edges, isEmpty);
      expect(notifications, 1);

      graph.clear(); // already empty
      expect(notifications, 1);
    });

    test('isLinear is true for a seeded chain, false once it branches', () {
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: const [
          TransposeTransform(semitones: 5, label: '+5'),
          TransposeTransform(semitones: 2, label: '+2'),
        ],
      );
      expect(graph.isLinear, isTrue);

      // A second edge off the source is a fan-out → no longer linear.
      final branch = graph.addNode(_t(12));
      graph.connect(TransformNodeId.source, branch.id);
      expect(graph.isLinear, isFalse);
    });

    test('isLinear is false when any edge is guarded', () {
      final s1 = EntityAddress.parse('state.s1');
      final graph = MidiTransformGraph(source: _clip([60]));
      final node = graph.addNode(_t(5));
      graph.connect(
        TransformNodeId.source,
        node.id,
        condition: StateMatchCondition(s1),
      );
      expect(graph.isLinear, isFalse);
    });

    test('an empty graph is trivially linear', () {
      expect(MidiTransformGraph(source: _clip([60])).isLinear, isTrue);
    });

    test('linearTransforms returns the spine in order for a linear graph', () {
      const transforms = [
        TransposeTransform(semitones: 5, label: '+5'),
        TransposeTransform(semitones: 2, label: '+2'),
      ];
      final graph = MidiTransformGraph.linear(
        source: _clip([60]),
        transforms: transforms,
      );

      final spine = graph.linearTransforms();
      expect(spine.map((t) => t.label), ['+5', '+2']);
    });

    test('linearTransforms follows the unconditional path past a branch', () {
      final s1 = EntityAddress.parse('state.s1');
      final graph = MidiTransformGraph(source: _clip([60]));
      // Main spine: source → +5 (unconditional).
      final main = graph.addNode(_t(5));
      graph.connect(TransformNodeId.source, main.id);
      // Guarded branch off the source that a chain can't hold.
      final branch = graph.addNode(_t(12));
      graph.connect(
        TransformNodeId.source,
        branch.id,
        condition: StateMatchCondition(s1),
      );

      expect(graph.isLinear, isFalse);
      // The extraction keeps the unconditional main path, dropping the branch.
      expect(graph.linearTransforms().map((t) => t.label), ['+5']);
    });
  });
}
