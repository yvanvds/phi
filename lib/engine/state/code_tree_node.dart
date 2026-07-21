import '../../domain/project/entity_address.dart';

/// An immutable view of one node in the `code.` library tree — a script entity
/// or a group folder — as the script library panel (issue #235) renders it.
///
/// [CodeLibraryController] flattens the registry's `code.` subtree into these,
/// preserving the registry's child order (which mirrors the persisted
/// `_group.json` order). A [group] carries its ordered [children]; a script is a
/// leaf with an empty [children] list. Both name themselves by their address
/// leaf, so the panel shows exactly the segment the registry addresses the node
/// by.
class CodeTreeNode {
  const CodeTreeNode({
    required this.address,
    required this.isGroup,
    this.children = const [],
  });

  /// The registry address of this node.
  final EntityAddress address;

  /// Whether this node is a group folder (`true`) or a script leaf (`false`).
  final bool isGroup;

  /// This group's children in display order — scripts and nested groups alike.
  /// Empty for a script leaf.
  final List<CodeTreeNode> children;

  /// The node's display name — its address leaf.
  String get name => address.name;
}
