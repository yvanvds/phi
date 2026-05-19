import 'patch_node_id.dart';
import 'patch_port.dart';

/// Globally-unique identity of a port within a patcher.
///
/// `(nodeId, side, index)` — used as a `Map` key by the canvas's
/// port-position lookup and as the source/target of a [PatchCable].
class PatchPortId {
  const PatchPortId({
    required this.nodeId,
    required this.side,
    required this.index,
  });

  final PatchNodeId nodeId;
  final PatchPortSide side;
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatchPortId &&
          other.nodeId == nodeId &&
          other.side == side &&
          other.index == index);

  @override
  int get hashCode => Object.hash(nodeId, side, index);

  @override
  String toString() => 'PatchPortId(${nodeId.value}, ${side.name}, $index)';
}
