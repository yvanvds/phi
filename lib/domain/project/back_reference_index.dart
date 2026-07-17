import 'entity_address.dart';

/// The registry's reverse map of references: for every target address, the set
/// of entities that point at it (design `docs/design/project-registry.md` §4).
///
/// References are stored *forward* on each entity (`voice.bells` → `mix.perc`);
/// this index is the inverse (`mix.perc` ← `voice.bells`), the thing that makes
/// two operations cheap:
///
/// - **Delete warnings** — before removing `mix.perc`, [referrersOf] lists who
///   still points at it.
/// - **Rename/move refactor** — renaming `mix.perc` finds every referent to
///   rewrite in one lookup rather than a full-tree scan.
///
/// A plain data structure with no tree knowledge: the [ProjectRegistry] owns one
/// and keeps it in step with the tree on every mutation. Both directions are
/// kept so a source's outgoing edges can be dropped in one call when the entity
/// is removed or re-indexed.
class BackReferenceIndex {
  final Map<EntityAddress, Set<EntityAddress>> _referrersByTarget = {};
  final Map<EntityAddress, Set<EntityAddress>> _targetsBySource = {};

  /// Records that [source] references every address in [targets]. Additive:
  /// call [removeSource] first to replace an entity's edges rather than union
  /// them. Empty [targets] records nothing.
  void add(EntityAddress source, Iterable<EntityAddress> targets) {
    for (final target in targets) {
      _targetsBySource.putIfAbsent(source, () => {}).add(target);
      _referrersByTarget.putIfAbsent(target, () => {}).add(source);
    }
  }

  /// Drops every outgoing edge recorded for [source], removing it from each
  /// target's referrer set. Incoming edges (entities that reference [source])
  /// are left untouched — after a delete they are exactly the dangling
  /// references the warning was about.
  void removeSource(EntityAddress source) {
    final targets = _targetsBySource.remove(source);
    if (targets == null) return;
    for (final target in targets) {
      final referrers = _referrersByTarget[target];
      if (referrers == null) continue;
      referrers.remove(source);
      if (referrers.isEmpty) _referrersByTarget.remove(target);
    }
  }

  /// The entities that reference [target], or an empty set if none do. The
  /// returned set is a defensive copy — callers may iterate it while mutating
  /// the index.
  Set<EntityAddress> referrersOf(EntityAddress target) => {
    ...?_referrersByTarget[target],
  };

  /// The addresses [source] points at, or an empty set. A defensive copy.
  Set<EntityAddress> referencesOf(EntityAddress source) => {
    ...?_targetsBySource[source],
  };

  /// Whether anything references [target].
  bool hasReferrers(EntityAddress target) =>
      _referrersByTarget[target]?.isNotEmpty ?? false;

  /// Forgets every edge. Used when the index is rebuilt from the tree after a
  /// structural refactor.
  void clear() {
    _referrersByTarget.clear();
    _targetsBySource.clear();
  }
}
