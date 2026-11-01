/// What one [FunctionEdit] does to a `.function`'s points (issue #475).
enum FunctionEditKind {
  /// A new point, sent as `<x> <y>`.
  add,

  /// A point moved, sent as the protocol's cell write `set <i> <x> <y>`, which
  /// keeps its curve.
  move,

  /// A point's arriving segment re-curved, `setcurve <i> <curve>`.
  curve,

  /// A point removed, `clear <i>`.
  remove,
}
