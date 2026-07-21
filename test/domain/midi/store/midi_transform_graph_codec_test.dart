import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/midi/graph/graph_eval_context.dart';
import 'package:phi/domain/midi/graph/midi_transform_graph.dart';
import 'package:phi/domain/midi/graph/state_match_condition.dart';
import 'package:phi/domain/midi/graph/transform_node_id.dart';
import 'package:phi/domain/midi/midi_clip.dart';
import 'package:phi/domain/midi/midi_note.dart';
import 'package:phi/domain/midi/store/midi_transform_graph_codec.dart';
import 'package:phi/domain/midi/transforms/transpose_transform.dart';
import 'package:phi/domain/project/entity_address.dart';

void main() {
  const codec = MidiTransformGraphCodec();

  MidiClip source() => MidiClip(
    bars: 1,
    notes: const [MidiNote(pitch: 60, start: 0, duration: 1, velocity: 0.5)],
  );

  List<double> pitches(List<MidiNote> notes) =>
      notes.map((n) => n.pitch).toList();

  test('a linear graph round-trips node-for-node', () {
    final clip = source();
    final graph = MidiTransformGraph.linear(
      source: clip,
      transforms: const [TransposeTransform(semitones: 12, label: 'up')],
    );
    addTearDown(graph.dispose);

    final decoded = codec.decode(codec.encode(graph), clip);
    addTearDown(decoded.dispose);

    expect(decoded.nodes, hasLength(1));
    expect(decoded.edges, hasLength(1));
    // Behaviour is preserved: both transpose the single note up an octave.
    expect(pitches(decoded.evaluate()), pitches(graph.evaluate()));
    expect(pitches(decoded.evaluate()), [72]);
  });

  test('a guarded branch round-trips its edge condition', () {
    final clip = source();
    final graph = MidiTransformGraph(source: clip);
    addTearDown(graph.dispose);
    final n0 = graph.addNode(
      const TransposeTransform(semitones: 12, label: 'a'),
    );
    final n1 = graph.addNode(
      const TransposeTransform(semitones: 12, label: 'b'),
    );
    graph.connect(TransformNodeId.source, n0.id);
    graph.connect(
      n0.id,
      n1.id,
      condition: StateMatchCondition(EntityAddress.parse('state.hot')),
    );

    final decoded = codec.decode(codec.encode(graph), clip);
    addTearDown(decoded.dispose);

    expect(decoded.nodes, hasLength(2));
    expect(decoded.edges, hasLength(2));

    const closed = GraphEvalContext.empty();
    final open = GraphEvalContext(
      activeState: EntityAddress.parse('state.hot'),
    );
    // Guard closed: only n0 fires (+12). Guard open: n0 → n1 (+24).
    expect(pitches(decoded.evaluate(closed)), pitches(graph.evaluate(closed)));
    expect(pitches(decoded.evaluate(open)), pitches(graph.evaluate(open)));
    expect(pitches(decoded.evaluate(closed)), [72]);
    expect(pitches(decoded.evaluate(open)), [84]);
  });

  test('edges may originate from the source sentinel', () {
    final clip = source();
    final graph = MidiTransformGraph(source: clip);
    addTearDown(graph.dispose);
    final n0 = graph.addNode(
      const TransposeTransform(semitones: 1, label: 'a'),
    );
    graph.connect(TransformNodeId.source, n0.id);

    final encoded = codec.encode(graph);
    final edge = (encoded['edges']! as List).first as Map<String, Object?>;
    expect(edge['from'], TransformNodeId.source.value);

    final decoded = codec.decode(encoded, clip);
    addTearDown(decoded.dispose);
    expect(pitches(decoded.evaluate()), [61]);
  });
}
