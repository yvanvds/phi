import 'registry_node.dart';

/// A named folder in the registry tree — a [RegistryGroup] nests other groups
/// and [RegistryEntity] leaves, enabling group-level addressing and (later)
/// group-level operations like `clip.drums.stop_all()`.
///
/// Children are keyed by name in a single map, which enforces two of the
/// design's rules for free: a group and an entity can never share a name at the
/// same level (they'd collide on one key), and — because every stored name is
/// already lowercase — case-insensitive sibling uniqueness reduces to plain key
/// uniqueness. Insertion order is preserved so listings are stable.
///
/// This node models the *shape* of the tree; enforcing the rules on mutation is
/// the [ProjectRegistry]'s job, so the setters here are intentionally low-level
/// and unchecked. Callers outside the registry should treat a group as
/// read-only.
class RegistryGroup extends RegistryNode {
  RegistryGroup(super.name);

  final Map<String, RegistryNode> _children = {};

  /// The direct children — groups and entities — in insertion order. Callers
  /// must not mutate the returned view.
  Iterable<RegistryNode> get children => _children.values;

  /// Whether this group has no children.
  bool get isEmpty => _children.isEmpty;

  /// The child named [name], or `null` if there is none.
  RegistryNode? child(String name) => _children[name];

  /// Whether a child named [name] exists.
  bool hasChild(String name) => _children.containsKey(name);

  /// Inserts or replaces the child keyed by its own name. Low-level: the
  /// registry checks name validity and clashes before calling this.
  void put(RegistryNode node) => _children[node.name] = node;

  /// Removes and returns the child named [name], or `null` if absent.
  RegistryNode? remove(String name) => _children.remove(name);

  /// Replaces the child keyed [oldName] with [node] (keyed by its own name) at
  /// the *same position*, preserving sibling insertion order — appending [node]
  /// when [oldName] is absent. The registry uses this so a same-parent rename
  /// keeps its place in the listing instead of being reinserted at the end (a
  /// plain [remove] + [put] would). Low-level: the registry checks name validity
  /// and clashes before calling this.
  void replaceChild(String oldName, RegistryNode node) {
    final rebuilt = <String, RegistryNode>{};
    var replaced = false;
    for (final entry in _children.entries) {
      if (entry.key == oldName) {
        rebuilt[node.name] = node;
        replaced = true;
      } else {
        rebuilt[entry.key] = entry.value;
      }
    }
    if (!replaced) rebuilt[node.name] = node;
    _children
      ..clear()
      ..addAll(rebuilt);
  }

  /// Moves every child out of [other] into this group, preserving order;
  /// [other] is left empty. Used to rehome a subtree when a move renames its
  /// root (whose own [name] is immutable), so the descendant nodes are reused
  /// rather than rebuilt.
  void adoptChildrenFrom(RegistryGroup other) {
    _children.addAll(other._children);
    other._children.clear();
  }
}
