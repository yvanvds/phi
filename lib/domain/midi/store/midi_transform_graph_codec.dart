import '../custom_transform_registry.dart';
import '../graph/midi_transform_graph.dart';
import '../graph/transform_node_id.dart';
import '../midi_clip.dart';
import 'edge_condition_codec.dart';
import 'midi_transform_codec.dart';

/// (De)serialises a whole [MidiTransformGraph] — the branching generalisation of
/// the linear chain — so a graph clip's nodes, edges and guards survive a
/// save/reload (issue #135).
///
/// Shape: `{nodes: [{id, transform}], edges: [{from, to, condition}]}`. Nodes
/// carry the [MidiTransform] each wraps (via [MidiTransformCodec]); edges carry
/// their `(from, to)` node ids and the [EdgeCondition] guard (via
/// [EdgeConditionCodec]). The implicit source vertex
/// ([TransformNodeId.source]) is never stored as a node, but edges may name it.
///
/// **Ids are remapped on load** (as [TransformNodeId] itself documents): [decode]
/// mints fresh node ids and rewires the stored edges through a
/// stored-id → fresh-id map, preserving structure without relying on ids being
/// stable across sessions. The source sentinel maps to itself.
class MidiTransformGraphCodec {
  /// Builds a codec. [transformCodec] (de)serialises each node's transform —
  /// pass one carrying a [CustomTransformRegistry] to re-link live-coded nodes.
  const MidiTransformGraphCodec({
    this.transformCodec = const MidiTransformCodec(),
    this.conditionCodec = const EdgeConditionCodec(),
  });

  /// The per-node transform codec.
  final MidiTransformCodec transformCodec;

  /// The per-edge condition codec.
  final EdgeConditionCodec conditionCodec;

  /// Flattens [graph] to a JSON-compatible map.
  Map<String, Object?> encode(MidiTransformGraph graph) => {
    'nodes': [
      for (final node in graph.nodes)
        {
          'id': node.id.value,
          'transform': transformCodec.encode(node.transform),
        },
    ],
    'edges': [
      for (final edge in graph.edges)
        {
          'from': edge.fromId.value,
          'to': edge.toId.value,
          'condition': conditionCodec.encode(edge.condition),
        },
    ],
  };

  /// Rebuilds a [MidiTransformGraph] over [source] from the map [encode]
  /// produced. Node ids are freshly minted and edges rewired through them;
  /// edges that the domain rejects (a stored cycle — impossible for a graph
  /// [MidiTransformGraph.connect] built) are simply skipped.
  MidiTransformGraph decode(Map<String, Object?> json, MidiClip source) {
    final graph = MidiTransformGraph(source: source);
    final idMap = <String, TransformNodeId>{
      TransformNodeId.source.value: TransformNodeId.source,
    };
    for (final raw in _list(json['nodes'])) {
      final map = _map(raw);
      final transform = transformCodec.decode(_map(map['transform']));
      final node = graph.addNode(transform);
      idMap[map['id'] as String? ?? node.id.value] = node.id;
    }
    for (final raw in _list(json['edges'])) {
      final map = _map(raw);
      final from = idMap[map['from']];
      final to = idMap[map['to']];
      if (from == null || to == null) continue;
      graph.connect(
        from,
        to,
        condition: conditionCodec.decode(_map(map['condition'])),
      );
    }
    return graph;
  }

  static Map<String, Object?> _map(Object? json) =>
      (json as Map).cast<String, Object?>();

  static List<Object?> _list(Object? json) =>
      (json as List?)?.cast<Object?>() ?? const [];
}
