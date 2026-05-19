import 'patch_port_id.dart';
import 'patch_port_kind.dart';

/// A connection from one node's output port to another's input port.
///
/// Immutable — to "move" a cable, remove and add. [kind] is duplicated
/// from the source port so the cable renderer doesn't have to dereference
/// the graph to pick solid-vs-dashed.
class PatchCable {
  const PatchCable({
    required this.source,
    required this.target,
    required this.kind,
  });

  /// Always an output port.
  final PatchPortId source;

  /// Always an input port.
  final PatchPortId target;

  final PatchPortKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchCable && other.source == source && other.target == target);

  @override
  int get hashCode => Object.hash(source, target);
}
