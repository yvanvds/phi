import '../../domain/project/entity_address.dart';

/// An immutable view of one node in a racks **definitions** tree — a `synth.` or
/// `fx.` entity, or a group folder — as the definitions panel (issue #209)
/// renders it.
///
/// [RackDefinitionsController] flattens each definition namespace (`synth.` and
/// `fx.`) into these, preserving the registry's child order (which mirrors the
/// persisted `_group.json` order). A [group] carries its ordered [children]; a
/// definition is a leaf with an empty [children] list. Both name themselves by
/// their address leaf. A leaf also carries its [kindTag] — the definition's own
/// kind name (`va`, `lowpass`, …) read off its payload — so the panel can show a
/// compact kind label beside the name without the surface decoding the payload.
class RackTreeNode {
  const RackTreeNode({
    required this.address,
    required this.isGroup,
    this.kindTag,
    this.children = const [],
  });

  /// The registry address of this node.
  final EntityAddress address;

  /// Whether this node is a group folder (`true`) or a definition leaf (`false`).
  final bool isGroup;

  /// The leaf definition's kind name (`sine` / `va` / `fm` / `sampler` for a
  /// synth; the [FxKind] name for an fx), or `null` for a group or an
  /// undecodable payload.
  final String? kindTag;

  /// This group's children in display order — definitions and nested groups
  /// alike. Empty for a definition leaf.
  final List<RackTreeNode> children;

  /// The node's display name — its address leaf.
  String get name => address.name;
}
