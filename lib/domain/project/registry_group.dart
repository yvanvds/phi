import 'entity_address.dart';
import 'reference_source.dart';
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
/// **Kind-declared group payloads (issue #165).** A group may itself carry an
/// entity [payload] — the "groups are buses" model of `docs/design/mix.md` §3,
/// where a `mix.` group *is* a bus with its own fader and sends. A plain
/// structural folder (a `clip.` group, an auto-created ancestor) leaves it
/// `null` and is unaffected. When a group carries a payload it also carries the
/// outgoing [references] that payload declares, so a group bus's sends feed the
/// back-reference index exactly like an entity's edges (delete-impact and
/// rename-refactor then cover them). Whether a payload is *persisted* is a
/// per-kind declaration the store owns; the tree stays kind-generic.
///
/// This node models the *shape* of the tree; enforcing the rules on mutation is
/// the [ProjectRegistry]'s job, so the setters here are intentionally low-level
/// and unchecked. Callers outside the registry should treat a group as
/// read-only.
class RegistryGroup extends RegistryNode {
  /// Builds a group, optionally carrying [payload] and the [references] it
  /// declares. A [ReferenceSource] payload's own references win; otherwise the
  /// explicit [references] are used (the same rule as [RegistryEntity]).
  RegistryGroup(
    super.name, {
    Object? payload,
    Set<EntityAddress> references = const {},
  }) : _payload = payload,
       _references = resolveReferences(payload, references);

  final Map<String, RegistryNode> _children = {};
  Object? _payload;
  Set<EntityAddress> _references;

  /// This group's own payload (a group bus's fader/sends for kinds that declare
  /// group payloads), or `null` for a plain structural folder. Opaque to the
  /// registry, exactly like an entity's payload.
  Object? get payload => _payload;

  /// The addresses this group's payload points at — the group's outgoing edges
  /// in the back-reference index. Unmodifiable; empty when the group carries no
  /// payload or references nothing.
  Set<EntityAddress> get references => _references;

  /// Replaces this group's [payload] and its resolved [references] in place,
  /// keeping the group's children and its position among its siblings. Used by
  /// the registry for an in-place payload edit and when a refactor rewrites the
  /// group's references. Re-derives the edge set from a [ReferenceSource]
  /// payload, else from [references]. Low-level: the registry keeps the
  /// back-reference index in step around this call.
  void assign(Object? payload, {Set<EntityAddress> references = const {}}) {
    _payload = payload;
    _references = resolveReferences(payload, references);
  }

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

  /// Moves the child named [name] to sit at [index] among its siblings,
  /// preserving every other child's relative order. [index] is the child's
  /// **final** position (0-based), clamped into range. A no-op when [name] is
  /// absent. The registry uses this to reorder a group's children — the
  /// `_group.json` order a Mix-surface section reorder writes (design
  /// `docs/design/mix.md` §7). Low-level: the registry notifies around it.
  void reorder(String name, int index) {
    if (!_children.containsKey(name)) return;
    final entries = _children.entries.toList();
    final from = entries.indexWhere((e) => e.key == name);
    final moved = entries.removeAt(from);
    final clamped = index.clamp(0, entries.length);
    entries.insert(clamped, moved);
    _children
      ..clear()
      ..addEntries(entries);
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
