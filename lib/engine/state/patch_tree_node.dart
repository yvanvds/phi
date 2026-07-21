import '../../domain/project/entity_address.dart';

/// An immutable view of one node in the `patch.` entity tree — a patch entity or
/// a group folder — as the patcher entity strip (issue #224) renders it.
///
/// [PatchLibraryController] flattens the registry's `patch.` subtree into these,
/// preserving the registry's child order (which mirrors the persisted
/// `_group.json` order). A [group] carries its ordered [children]; a patch is a
/// leaf with an empty [children] list. Both name themselves by their address
/// leaf, so the strip shows exactly the segment the registry addresses the node
/// by (the patcher analogue of `ClipTreeNode`).
class PatchTreeNode {
  const PatchTreeNode({
    required this.address,
    required this.isGroup,
    this.children = const [],
  });

  /// The registry address of this node.
  final EntityAddress address;

  /// Whether this node is a group folder (`true`) or a patch leaf (`false`).
  final bool isGroup;

  /// This group's children in display order — patches and nested groups alike.
  /// Empty for a patch leaf.
  final List<PatchTreeNode> children;

  /// The node's display name — its address leaf.
  String get name => address.name;
}
