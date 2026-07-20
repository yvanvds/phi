import 'drop_edge.dart';
import 'layout_node.dart';
import 'split_axis.dart';

/// The shell's workspace arrangement — the split tree, its tab stacks and active
/// tabs — as one serialisable value (design `docs/design/shell-layout.md` §2,
/// §3). This is the "layout section" the project manifest will carry (wiring it
/// into `project.json` is a later slice); here it is the pure-Dart domain model.
///
/// **Invariants** every operation preserves (and [fromJson]/[fit] repair):
///
/// 1. A split's [LayoutSplit.fractions] are positive and sum to 1 — geometry is
///    resolution-independent, so it degrades gracefully on a smaller screen.
/// 2. There is always at least one pane; the **last pane is never removed** (it
///    may sit empty).
/// 3. A surface id appears **at most once** across the whole tree — surfaces are
///    single-instance, so a move never duplicates one.
/// 4. A pane's [LayoutPane.active] is a live tab (null only when the pane is
///    empty).
/// 5. Node ids are unique and non-empty; a split has at least two children (a
///    lone child collapses into its parent's slot).
///
/// Operations ([split], [join], [reorderTab], [close], [moveSurface], [resize])
/// return a **new** layout, leaving this one untouched.
class ShellLayout {
  /// Builds a layout around a [root] node. The constructor does not validate or
  /// repair — [fromJson], [fit] and the operations are what keep the invariants;
  /// construct directly only with a well-formed tree (the seed, or a test).
  const ShellLayout({required this.root, this.version = currentVersion});

  /// The seed layout: a single pane holding [mixSurfaceId] (design §3 — "a fresh
  /// project seeds the current single-pane layout with Mix open"). The id is a
  /// `SurfaceId.name` string on the shell side; it defaults to `mix`.
  factory ShellLayout.seed([String mixSurfaceId = 'mix']) => ShellLayout(
    root: LayoutPane(id: 'p1', tabs: [mixSurfaceId], active: mixSurfaceId),
  );

  /// Reads a layout from the decoded manifest section, then repairs it so the
  /// invariants always hold: duplicate surfaces and empty panes drop, lone-child
  /// splits collapse, ids are made unique, actives are pinned to live tabs and
  /// fractions are renormalised. A malformed or missing `root` becomes an empty
  /// single pane.
  factory ShellLayout.fromJson(Map<String, Object?> json) {
    final rootJson = json['root'];
    final root = rootJson is Map
        ? LayoutNode.fromJson(rootJson.cast<String, Object?>())
        : const LayoutPane(id: 'p1');
    final version = (json['version'] as num?)?.toInt() ?? currentVersion;
    return ShellLayout(root: root, version: version)._sanitised();
  }

  /// The current layout-section schema version. Bump when the shape changes in a
  /// way that needs a load-time migration.
  static const int currentVersion = 1;

  /// The smallest slice a pane may be clamped to under fit-fallback, so no pane
  /// collapses to nothing on a smaller screen (5% of its split).
  static const double minFraction = 0.05;

  /// The root of the split tree — a [LayoutPane] (single-pane layout) or a
  /// [LayoutSplit].
  final LayoutNode root;

  /// The layout-section schema version this layout was written with.
  final int version;

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Every pane in the tree, in depth-first order.
  List<LayoutPane> get panes {
    final out = <LayoutPane>[];
    void walk(LayoutNode node) {
      if (node is LayoutPane) {
        out.add(node);
      } else if (node is LayoutSplit) {
        node.children.forEach(walk);
      }
    }

    walk(root);
    return out;
  }

  /// The number of panes — at least 1.
  int get paneCount => panes.length;

  /// Every surface id currently placed in a pane (the complement of the "closed"
  /// set, design §2).
  Set<String> get placedSurfaces => {for (final pane in panes) ...pane.tabs};

  /// The surfaces that are *not* placed — the "closed" set the rail/palette can
  /// summon, given the app's [known] surface universe (design §3).
  Set<String> closedSurfaces(Set<String> known) =>
      known.difference(placedSurfaces);

  /// The id of the pane holding [surfaceId], or null when it is closed.
  String? paneIdOf(String surfaceId) {
    for (final pane in panes) {
      if (pane.tabs.contains(surfaceId)) return pane.id;
    }
    return null;
  }

  /// The pane with [id], or null.
  LayoutPane? paneById(String id) {
    for (final pane in panes) {
      if (pane.id == id) return pane;
    }
    return null;
  }

  /// The node with [id] anywhere in the tree, or null.
  LayoutNode? nodeById(String id) => _find(root, id);

  // ---------------------------------------------------------------------------
  // Operations — each returns a new layout, preserving the invariants
  // ---------------------------------------------------------------------------

  /// Splits [targetPaneId] by dropping [surfaceId] on one of its [edge]s, putting
  /// the surface in a fresh pane beside/above/below the target (design §2 — edge
  /// drops). The surface is removed from wherever it currently lives first, so it
  /// is never duplicated. When the target already sits in a split of the same
  /// [SplitAxis], the new pane joins as a sibling (an n-ary row/column); a
  /// contested slot is otherwise wrapped in a new two-pane split, 50/50.
  ///
  /// Dropping a pane's only tab onto that same pane is a no-op, as is an unknown
  /// target. [newPaneId]/[newSplitId] override the generated ids (handy in
  /// tests); they must not already be in use.
  ShellLayout split(
    String targetPaneId,
    String surfaceId,
    DropEdge edge, {
    String? newPaneId,
    String? newSplitId,
  }) {
    final target = paneById(targetPaneId);
    if (target == null) return this;
    // Dragging a pane's sole tab onto itself changes nothing.
    if (target.tabs.length == 1 && target.tabs.first == surfaceId) return this;

    final work = _removed(surfaceId);
    final movedTarget = work.paneById(targetPaneId);
    if (movedTarget == null) return this;

    final used = work._usedIds();
    final paneId = newPaneId ?? _freshId('p', used);
    used.add(paneId);
    final newPane = LayoutPane(
      id: paneId,
      tabs: [surfaceId],
      active: surfaceId,
    );

    final parent = work._parentSplitOf(targetPaneId);
    if (parent != null && parent.axis == edge.axis) {
      // Extend the existing row/column: carve the target's slice in two.
      final at = parent.children.indexWhere((c) => c.id == targetPaneId);
      final children = [...parent.children];
      final fractions = [...parent.fractions];
      final half = fractions[at] / 2;
      fractions[at] = half;
      final insertAt = edge.placesBefore ? at : at + 1;
      children.insert(insertAt, newPane);
      fractions.insert(insertAt, half);
      return work._replacing(
        parent.id,
        parent.copyWith(children: children, fractions: fractions),
      );
    }

    // Wrap the target in a new two-child split along the drop axis.
    final splitId = newSplitId ?? _freshId('s', used);
    final children = edge.placesBefore
        ? <LayoutNode>[newPane, movedTarget]
        : <LayoutNode>[movedTarget, newPane];
    return work._replacing(
      targetPaneId,
      LayoutSplit(
        id: splitId,
        axis: edge.axis,
        children: children,
        fractions: const [0.5, 0.5],
      ),
    );
  }

  /// Joins [surfaceId] into [targetPaneId]'s tab stack (design §2 — a drop on the
  /// pane centre): it is removed from its old pane, appended to the target and
  /// made active. Unknown target → no-op.
  ShellLayout join(String targetPaneId, String surfaceId) =>
      moveSurface(surfaceId, targetPaneId);

  /// Moves [surfaceId] into [toPaneId] at [atIndex] (default: the end),
  /// activating it there — the primitive behind a cross-pane drag. Removing it
  /// from its old pane first upholds the single-instance invariant; if that
  /// empties the old pane it is pruned (unless it is the last pane). Moving a
  /// pane's only tab onto that same pane, or naming an unknown target, is a
  /// no-op.
  ShellLayout moveSurface(String surfaceId, String toPaneId, {int? atIndex}) {
    if (paneById(toPaneId) == null) return this;

    final work = _removed(surfaceId);
    final target = work.paneById(toPaneId);
    if (target == null) return this; // target was the surface's sole-tab pane.

    final tabs = [...target.tabs];
    final index = (atIndex ?? tabs.length).clamp(0, tabs.length);
    tabs.insert(index, surfaceId);
    return work._replacing(
      toPaneId,
      target.copyWith(tabs: tabs, active: surfaceId),
    );
  }

  /// Makes [surfaceId] the active (foreground) tab of whichever pane holds it —
  /// the layout side of a rail summon focusing an already-placed surface (design
  /// §2 — "clicking a rail entry focuses the surface wherever it lives"). A no-op
  /// when the surface is closed or is already its pane's active tab.
  ShellLayout activate(String surfaceId) {
    final paneId = paneIdOf(surfaceId);
    if (paneId == null) return this;
    final pane = paneById(paneId)!;
    if (pane.active == surfaceId) return this;
    return _replacing(paneId, pane.copyWith(active: surfaceId));
  }

  /// Reorders a tab within [paneId] from [oldIndex] to [newIndex], keeping the
  /// active tab (design §2 — "within a stack to reorder"). Out-of-range indices
  /// or an unknown pane → no-op.
  ShellLayout reorderTab(String paneId, int oldIndex, int newIndex) {
    final pane = paneById(paneId);
    if (pane == null) return this;
    if (oldIndex < 0 || oldIndex >= pane.tabs.length) return this;
    final tabs = [...pane.tabs];
    final moved = tabs.removeAt(oldIndex);
    tabs.insert(newIndex.clamp(0, tabs.length), moved);
    return _replacing(paneId, pane.copyWith(tabs: tabs));
  }

  /// Closes [surfaceId] — removing it from its pane, returning it to the "closed"
  /// set (design §2). An emptied pane is pruned and its split collapses, except
  /// the last pane, which stays (empty). Closing an unplaced surface → no-op.
  ShellLayout close(String surfaceId) => _removed(surfaceId);

  /// Sets the [fractions] of the split with [splitId], clamped to [minFraction]
  /// and renormalised to sum to 1 (design §2 — splitter resize; the clamp is also
  /// fit-fallback for a smaller screen). A length mismatch or a non-split target
  /// → no-op.
  ShellLayout resize(String splitId, List<double> fractions) {
    final node = nodeById(splitId);
    if (node is! LayoutSplit) return this;
    if (fractions.length != node.children.length) return this;
    return _replacing(
      splitId,
      node.copyWith(fractions: _clampNormalise(fractions)),
    );
  }

  /// Fit-fallback (design §3): drops any tab whose surface id is not in [known]
  /// (a surface the app no longer carries), then repairs the tree and clamps
  /// every split's fractions to [minFraction] so a layout restored onto a smaller
  /// screen stays usable. All surfaces unknown → a single empty pane survives.
  ShellLayout fit(Set<String> known) {
    LayoutNode drop(LayoutNode node) {
      if (node is LayoutPane) {
        final tabs = [
          for (final tab in node.tabs)
            if (known.contains(tab)) tab,
        ];
        return LayoutPane(
          id: node.id,
          tabs: tabs,
          active: node.active != null && tabs.contains(node.active)
              ? node.active
              : (tabs.isEmpty ? null : tabs.first),
        );
      }
      final split = node as LayoutSplit;
      return split.copyWith(
        children: [for (final c in split.children) drop(c)],
      );
    }

    final dropped = ShellLayout(
      root: drop(root),
      version: version,
    )._sanitised();

    LayoutNode clamp(LayoutNode node) {
      if (node is! LayoutSplit) return node;
      return node.copyWith(
        children: [for (final c in node.children) clamp(c)],
        fractions: _clampNormalise(node.fractions),
      );
    }

    return ShellLayout(root: clamp(dropped.root), version: version);
  }

  /// The layout as the JSON map stored in the manifest's layout section.
  Map<String, Object?> toJson() => {'version': version, 'root': root.toJson()};

  ShellLayout copyWith({LayoutNode? root, int? version}) =>
      ShellLayout(root: root ?? this.root, version: version ?? this.version);

  // ---------------------------------------------------------------------------
  // Internal tree surgery
  // ---------------------------------------------------------------------------

  /// This layout with [surfaceId] stripped from its pane and the tree repaired
  /// (empty panes pruned, lone splits collapsed, the last pane kept).
  ShellLayout _removed(String surfaceId) =>
      ShellLayout(root: _strip(root, surfaceId), version: version)._sanitised();

  /// [node] with [surfaceId] removed from whichever pane holds it, re-picking a
  /// neighbouring active tab; panes may be left empty (pruning is [_sanitised]'s
  /// job).
  static LayoutNode _strip(LayoutNode node, String surfaceId) {
    if (node is LayoutPane) {
      final at = node.tabs.indexOf(surfaceId);
      if (at < 0) return node;
      final tabs = [...node.tabs]..removeAt(at);
      var active = node.active;
      if (active == surfaceId) {
        active = tabs.isEmpty
            ? null
            : tabs[at < tabs.length ? at : tabs.length - 1];
      }
      return LayoutPane(id: node.id, tabs: tabs, active: active);
    }
    final split = node as LayoutSplit;
    return split.copyWith(
      children: [for (final c in split.children) _strip(c, surfaceId)],
    );
  }

  /// This layout with the node identified by [id] swapped for [replacement].
  ShellLayout _replacing(String id, LayoutNode replacement) =>
      ShellLayout(root: _replace(root, id, replacement), version: version);

  static LayoutNode _replace(
    LayoutNode node,
    String id,
    LayoutNode replacement,
  ) {
    if (node.id == id) return replacement;
    if (node is LayoutSplit) {
      return node.copyWith(
        children: [for (final c in node.children) _replace(c, id, replacement)],
      );
    }
    return node;
  }

  static LayoutNode? _find(LayoutNode node, String id) {
    if (node.id == id) return node;
    if (node is LayoutSplit) {
      for (final child in node.children) {
        final hit = _find(child, id);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// The split whose direct children include the node with [childId], or null
  /// when that node is the root.
  LayoutSplit? _parentSplitOf(String childId) {
    LayoutSplit? search(LayoutNode node) {
      if (node is! LayoutSplit) return null;
      for (final child in node.children) {
        if (child.id == childId) return node;
        final deeper = search(child);
        if (deeper != null) return deeper;
      }
      return null;
    }

    return search(root);
  }

  Set<String> _usedIds() {
    final ids = <String>{};
    void walk(LayoutNode node) {
      ids.add(node.id);
      if (node is LayoutSplit) node.children.forEach(walk);
    }

    walk(root);
    return ids;
  }

  /// Returns a repaired copy: duplicate surfaces and empty panes drop, lone-child
  /// splits collapse into their slot, ids are made unique and non-empty, actives
  /// are pinned to a live tab and fractions renormalised — and at least one pane
  /// always survives. Idempotent, and a no-op on an already-valid tree (so a
  /// round-trip through JSON is exact).
  ShellLayout _sanitised() {
    final seenSurfaces = <String>{};
    final seenIds = <String>{};

    LayoutNode? walk(LayoutNode node) {
      if (node is LayoutPane) {
        final tabs = [
          for (final tab in node.tabs)
            if (seenSurfaces.add(tab)) tab,
        ];
        if (tabs.isEmpty) return null;
        return LayoutPane(
          id: _uniqueId(node.id, 'p', seenIds),
          tabs: tabs,
          active: node.active != null && tabs.contains(node.active)
              ? node.active
              : tabs.first,
        );
      }
      final split = node as LayoutSplit;
      final kept = <LayoutNode>[];
      final fractions = <double>[];
      for (var i = 0; i < split.children.length; i++) {
        final child = walk(split.children[i]);
        if (child != null) {
          kept.add(child);
          fractions.add(i < split.fractions.length ? split.fractions[i] : 0);
        }
      }
      if (kept.isEmpty) return null;
      if (kept.length == 1) return kept.first;
      return LayoutSplit(
        id: _uniqueId(split.id, 's', seenIds),
        axis: split.axis,
        children: kept,
        fractions: _normalise(fractions),
      );
    }

    final repaired = walk(root) ?? LayoutPane(id: _uniqueId('', 'p', seenIds));
    return ShellLayout(root: repaired, version: version);
  }

  /// Keeps [current] if it is non-empty and unseen, otherwise mints the smallest
  /// fresh `prefix<n>`; records the result in [seen].
  static String _uniqueId(String current, String prefix, Set<String> seen) {
    if (current.isNotEmpty && seen.add(current)) return current;
    var n = 1;
    while (!seen.add('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }

  /// The smallest `prefix<n>` not already in [used].
  static String _freshId(String prefix, Set<String> used) {
    var n = 1;
    while (used.contains('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }

  /// Replaces non-positive/non-finite entries with [minFraction], then scales the
  /// list to sum to 1. A well-formed list (all positive, sum 1) is returned
  /// unchanged, so a round-trip is exact.
  static List<double> _normalise(List<double> fractions) {
    final cleaned = [
      for (final f in fractions) f.isFinite && f > 0 ? f : minFraction,
    ];
    final total = cleaned.fold<double>(0, (sum, f) => sum + f);
    if (total <= 0) {
      final share = 1.0 / cleaned.length;
      return [for (final _ in cleaned) share];
    }
    return [for (final f in cleaned) f / total];
  }

  /// Clamps each entry to `[minFraction, 1]` then scales to sum to 1 — the
  /// fit-fallback that stops any pane collapsing on a smaller screen.
  static List<double> _clampNormalise(List<double> fractions) {
    final clamped = [
      for (final f in fractions)
        f.isFinite ? f.clamp(minFraction, 1.0).toDouble() : minFraction,
    ];
    final total = clamped.fold<double>(0, (sum, f) => sum + f);
    return [for (final f in clamped) f / total];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellLayout && other.version == version && other.root == root;

  @override
  int get hashCode => Object.hash(version, root);

  @override
  String toString() => 'ShellLayout(v$version, $root)';
}
