/// What one [NodesEdit] does to a `.nodes` object (issue #476).
enum NodesEditKind {
  /// The cursor moved, sent as `<x> <y>` — the object answers with the
  /// distances and the weights.
  cursor,

  /// A node moved, sent as the protocol's cell write `set <i> <x> <y>`, which
  /// keeps its radius.
  move,

  /// A node's radius changed, sent as `set <i> <x> <y> <radius>`.
  resize,
}
