import '../midi_transform.dart';
import 'transform_node_id.dart';

/// One vertex in a [MidiTransformGraph]: an id plus the [MidiTransform] it
/// applies to the notes arriving along its incoming edges.
///
/// Thin and immutable — the wrapped transform already carries `active` and
/// `label`, so the node adds only identity. A node whose transform is
/// inactive passes its input through unchanged (the graph counterpart of the
/// chain skipping an inactive stage).
class TransformNode {
  const TransformNode({required this.id, required this.transform});

  final TransformNodeId id;
  final MidiTransform transform;

  TransformNode copyWith({MidiTransform? transform}) =>
      TransformNode(id: id, transform: transform ?? this.transform);
}
