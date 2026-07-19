import '../../domain/project/entity_address.dart';

/// An immutable view of one node in the `clip.` library tree — a clip entity or
/// a group folder — as the library panel (issue #188) renders it.
///
/// [ClipLibraryController] flattens the registry's `clip.` subtree into these,
/// preserving the registry's child order (which mirrors the persisted
/// `_group.json` order). A [group] carries its ordered [children]; a clip is a
/// leaf with an empty [children] list. Both name themselves by their address
/// leaf (the one-name rule, design §3), so the panel shows exactly the segment
/// the registry addresses the node by.
class ClipTreeNode {
  const ClipTreeNode({
    required this.address,
    required this.isGroup,
    this.children = const [],
  });

  /// The registry address of this node.
  final EntityAddress address;

  /// Whether this node is a group folder (`true`) or a clip leaf (`false`).
  final bool isGroup;

  /// This group's children in display order — clips and nested groups alike.
  /// Empty for a clip leaf.
  final List<ClipTreeNode> children;

  /// The node's display name — its address leaf.
  String get name => address.name;
}
