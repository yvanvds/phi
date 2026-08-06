import '../../domain/patcher/patch_port_kind.dart';

/// One copied cable, endpoints expressed as **indices into the clipboard's
/// node list** rather than live [PatchNodeId]s — the copied objects may be
/// deleted (or belong to another patch entirely) by the time this is pasted,
/// so the clipboard can reference nothing that has to stay alive.
class PatchClipboardCable {
  const PatchClipboardCable({
    required this.sourceNode,
    required this.sourceOutlet,
    required this.targetNode,
    required this.targetInlet,
    required this.kind,
  });

  /// Index of the source node in [PatchClipboardData.nodes].
  final int sourceNode;

  /// Outlet index on the source node.
  final int sourceOutlet;

  /// Index of the target node in [PatchClipboardData.nodes].
  final int targetNode;

  /// Inlet index on the target node.
  final int targetInlet;

  final PatchPortKind kind;
}
