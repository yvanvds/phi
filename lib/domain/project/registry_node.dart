/// A node in the [ProjectRegistry] tree — either a [RegistryGroup] (a named
/// folder that nests) or a [RegistryEntity] (a named leaf owning a payload).
///
/// Nodes are deliberately position-unaware: they carry only their own [name]
/// segment, never a parent pointer or a full address. Where a node sits is the
/// registry's business, so moving a subtree is a pointer swap in one map rather
/// than a walk that rewrites every descendant. Build a node's [EntityAddress]
/// from its parent group's address plus [name] when you need one.
///
/// This is a plain `abstract` base (not `sealed`) so the two concrete kinds can
/// live in their own files, matching the one-class-per-file layout; branch on
/// the node with `is RegistryGroup` / `is RegistryEntity`.
abstract class RegistryNode {
  RegistryNode(this.name);

  /// This node's own path segment — a valid [NameValidator] name. A kind root's
  /// name is the kind itself.
  final String name;
}
