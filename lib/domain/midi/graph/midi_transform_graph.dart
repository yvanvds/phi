import 'package:flutter/foundation.dart';

import '../midi_clip.dart';
import '../midi_note.dart';
import '../midi_transform.dart';
import 'always_condition.dart';
import 'edge_condition.dart';
import 'graph_eval_context.dart';
import 'transform_edge.dart';
import 'transform_node.dart';
import 'transform_node_id.dart';

/// A directed acyclic graph of [MidiTransform]s applied to a source
/// [MidiClip] — the branching generalisation of [MidiTransformChain]
/// (vision §3.7).
///
/// The clip is the implicit [TransformNodeId.source] vertex. Notes flow along
/// [TransformEdge]s whose [EdgeCondition] is open for the current
/// [GraphEvalContext]; each node applies its (active) transform to the merged
/// notes arriving on its incoming edges. A node may fan out to several edges —
/// its output is **broadcast** down every open branch — and fan in from
/// several, whose outputs **merge**. The graph result is the concatenation of
/// every reachable *terminal* node's output (a node with no open outgoing
/// edge), so a two-way branch yields the union of both leaves.
///
/// A linear chain is the degenerate case: [MidiTransformGraph.linear] wires
/// `source → t0 → t1 → …` with unconditional edges, and [evaluate] then
/// matches [MidiTransformChain.output] note-for-note — keeping the simple case
/// usable while the DAG carries the branching cases.
///
/// Acyclicity is an invariant, not a hope: [connect] rejects any edge that
/// would close a cycle, so [evaluate] can assume a topological order exists.
///
/// Mutates in place via [addNode] / [removeNode] / [connect] / [disconnect] /
/// [setNodeTransform]; each mutation bumps [version] and notifies, matching
/// [MidiTransformChain] and [StateGraph].
class MidiTransformGraph extends ChangeNotifier {
  MidiTransformGraph({required MidiClip source}) : _source = source;

  /// Builds a linear graph equivalent to a [MidiTransformChain]: the source
  /// feeds the first transform, each transform feeds the next, all edges
  /// unconditional. [evaluate] then equals the chain's `output`.
  factory MidiTransformGraph.linear({
    required MidiClip source,
    List<MidiTransform> transforms = const [],
  }) {
    final graph = MidiTransformGraph(source: source);
    var previous = TransformNodeId.source;
    for (final t in transforms) {
      final node = graph.addNode(t);
      graph.connect(previous, node.id);
      previous = node.id;
    }
    return graph;
  }

  final MidiClip _source;
  final Map<TransformNodeId, TransformNode> _nodes = {};
  final List<TransformEdge> _edges = [];
  int _version = 0;

  // Single-slot memo for [evaluate], keyed on everything that can change the
  // result: the structural [version], the source clip's [MidiClip.revision],
  // the summed node-transform revisions (hot-reload), and the eval context.
  List<MidiNote>? _cache;
  int _cacheVersion = -1;
  int _cacheSourceRevision = -1;
  int _cacheTransformsRevision = -1;
  GraphEvalContext? _cacheContext;

  MidiClip get source => _source;

  List<TransformNode> get nodes => List.unmodifiable(_nodes.values);

  List<TransformEdge> get edges => List.unmodifiable(_edges);

  /// Monotonic counter bumped on every mutating call, for cheap
  /// `shouldRepaint` comparisons.
  int get version => _version;

  TransformNode? nodeById(TransformNodeId id) => _nodes[id];

  // ─── mutation ──────────────────────────────────────────────────────────

  /// Add a node wrapping [transform] under a fresh id and return it. The node
  /// starts disconnected; use [connect] to wire it in.
  TransformNode addNode(MidiTransform transform) {
    final node = TransformNode(
      id: TransformNodeId.next(),
      transform: transform,
    );
    _nodes[node.id] = node;
    _bump();
    return node;
  }

  /// Remove [id] and every edge touching it. No-op if [id] is unknown or is
  /// the source sentinel.
  void removeNode(TransformNodeId id) {
    if (id.isSource) return;
    if (_nodes.remove(id) == null) return;
    _edges.removeWhere((e) => e.fromId == id || e.toId == id);
    _bump();
  }

  /// Connect [from] → [to] under [condition] (unconditional by default).
  ///
  /// Rejects — returning `false` without mutating — when: [to] is the source
  /// sentinel; either endpoint is an unknown node ([from] may be the source
  /// sentinel); an edge for the `(from, to)` pair already exists; or the edge
  /// would close a cycle. Returns `true` and notifies on success.
  bool connect(
    TransformNodeId from,
    TransformNodeId to, {
    EdgeCondition condition = const AlwaysCondition(),
  }) {
    if (to.isSource) return false;
    if (!from.isSource && !_nodes.containsKey(from)) return false;
    if (!_nodes.containsKey(to)) return false;
    if (from == to) return false;
    if (_edges.any((e) => e.fromId == from && e.toId == to)) return false;
    // A new from→to edge closes a cycle iff `to` can already reach `from`.
    if (_canReach(to, from)) return false;
    _edges.add(TransformEdge(fromId: from, toId: to, condition: condition));
    _bump();
    return true;
  }

  /// Remove the edge for the `(from, to)` pair, whatever its condition. No-op
  /// if no such edge exists.
  void disconnect(TransformNodeId from, TransformNodeId to) {
    final before = _edges.length;
    _edges.removeWhere((e) => e.fromId == from && e.toId == to);
    if (_edges.length != before) _bump();
  }

  /// Replace the transform on [id] (e.g. to toggle `active` or swap
  /// parameters). No-op if [id] is unknown.
  void setNodeTransform(TransformNodeId id, MidiTransform transform) {
    final node = _nodes[id];
    if (node == null) return;
    _nodes[id] = node.copyWith(transform: transform);
    _bump();
  }

  /// Toggle the `active` flag on [id]'s transform. No-op if [id] is unknown or
  /// already in that state.
  void setActive(TransformNodeId id, bool active) {
    final node = _nodes[id];
    if (node == null || node.transform.active == active) return;
    _nodes[id] = node.copyWith(
      transform: node.transform.copyWith(active: active),
    );
    _bump();
  }

  /// Signals that the source clip's contents changed underneath the graph
  /// (e.g. a file import mutated it in place). Bumps [version] and notifies.
  void notifySourceChanged() => _bump();

  // ─── evaluation ──────────────────────────────────────────────────────────

  /// A topological order of the real nodes, or `null` if the graph contains a
  /// cycle. [connect] keeps the graph acyclic, so a `null` here means the
  /// graph was assembled through some other path — callers may treat it as an
  /// invariant violation. Source-originating edges are folded in by seeding
  /// the source's out-degree contribution.
  List<TransformNodeId>? topologicalOrder() {
    final inDegree = <TransformNodeId, int>{
      for (final id in _nodes.keys) id: 0,
    };
    for (final e in _edges) {
      if (e.fromId.isSource) continue; // source is not a counted vertex
      if (inDegree.containsKey(e.toId)) {
        inDegree[e.toId] = inDegree[e.toId]! + 1;
      }
    }
    final ready = [
      for (final entry in inDegree.entries)
        if (entry.value == 0) entry.key,
    ];
    final order = <TransformNodeId>[];
    while (ready.isNotEmpty) {
      // FIFO so the order — and thus the note order of broadcast terminals —
      // follows node/edge insertion rather than a LIFO stack's reversal.
      final id = ready.removeAt(0);
      order.add(id);
      for (final e in _edges) {
        if (e.fromId != id) continue;
        final next = inDegree[e.toId];
        if (next == null) continue;
        inDegree[e.toId] = next - 1;
        if (inDegree[e.toId] == 0) ready.add(e.toId);
      }
    }
    return order.length == _nodes.length ? order : null;
  }

  /// Whether the graph currently contains a cycle.
  bool get hasCycle => topologicalOrder() == null;

  /// The notes produced by walking the active subgraph for [context].
  ///
  /// Starts from the source clip, applies each reachable node's transform to
  /// the merged notes on its open incoming edges (inactive transforms pass
  /// through), and returns the concatenation of every reachable terminal
  /// node's output. When no node is reachable — an empty graph, or one whose
  /// source edges are all closed — the source clip's notes pass through
  /// unchanged.
  ///
  /// The player reads this live each tick (~60×/sec), so it is memoised in a
  /// single slot: the walk only re-runs when the graph structure changed
  /// (tracked by [version]), the source clip was edited ([MidiClip.revision]),
  /// a node transform hot-reloaded ([MidiTransform.revision]), or the [context]
  /// differs from the last call (a state flip). Between those, repeated reads
  /// with the same context return the cached list instance — an O(1) hit, not a
  /// fresh walk. Callers must treat the result as read-only; mutating it
  /// corrupts the cache.
  ///
  /// The slot holds one context at a time, so alternating calls with two
  /// different contexts recompute each time; in practice the preview and the
  /// player evaluate against the same live context, so the slot stays warm.
  List<MidiNote> evaluate([
    GraphEvalContext context = const GraphEvalContext.empty(),
  ]) {
    final sourceRevision = _source.revision;
    final transformsRevision = _transformsRevision;
    if (_cache != null &&
        _cacheVersion == _version &&
        _cacheSourceRevision == sourceRevision &&
        _cacheTransformsRevision == transformsRevision &&
        _cacheContext == context) {
      return _cache!;
    }
    final result = _evaluate(context);
    _cache = result;
    _cacheVersion = _version;
    _cacheSourceRevision = sourceRevision;
    _cacheTransformsRevision = transformsRevision;
    _cacheContext = context;
    return result;
  }

  /// Sum of the node transforms' own revisions — bumps when a chip hot-reloads
  /// under a stable graph. Folded into the [evaluate] cache key, mirroring
  /// [MidiTransformChain]. Revisions only increment, so any hot-reload strictly
  /// increases the sum.
  int get _transformsRevision {
    var sum = 0;
    for (final node in _nodes.values) {
      sum += node.transform.revision;
    }
    return sum;
  }

  /// The uncached walk of the active subgraph for [context]. See [evaluate].
  List<MidiNote> _evaluate(GraphEvalContext context) {
    final order = topologicalOrder();
    if (order == null) {
      throw StateError('MidiTransformGraph.evaluate called on a cyclic graph');
    }

    // Nodes reachable from the source along edges open under `context`.
    final reachable = _reachableFromSource(context);
    if (reachable.isEmpty) return List<MidiNote>.of(_source.notes);

    // Fold node outputs in topological order so every predecessor is done
    // before its successors read it.
    final outputs = <TransformNodeId, List<MidiNote>>{
      TransformNodeId.source: List<MidiNote>.of(_source.notes),
    };
    for (final id in order) {
      if (!reachable.contains(id)) continue;
      final input = <MidiNote>[];
      for (final e in _edges) {
        if (e.toId != id) continue;
        if (!e.condition.isSatisfiedBy(context)) continue;
        final upstream = outputs[e.fromId];
        if (upstream != null) input.addAll(upstream);
      }
      final node = _nodes[id]!;
      outputs[id] = node.transform.active ? node.transform.apply(input) : input;
    }

    // Terminals: reachable nodes with no open outgoing edge to another node.
    final result = <MidiNote>[];
    for (final id in order) {
      if (!reachable.contains(id)) continue;
      final hasOpenOut = _edges.any(
        (e) =>
            e.fromId == id &&
            e.condition.isSatisfiedBy(context) &&
            reachable.contains(e.toId),
      );
      if (!hasOpenOut) result.addAll(outputs[id]!);
    }
    return result;
  }

  // ─── internals ───────────────────────────────────────────────────────────

  /// Nodes reachable from the source following only edges open under
  /// [context]. BFS from the source sentinel.
  Set<TransformNodeId> _reachableFromSource(GraphEvalContext context) {
    final reached = <TransformNodeId>{};
    final frontier = <TransformNodeId>[TransformNodeId.source];
    while (frontier.isNotEmpty) {
      final id = frontier.removeLast();
      for (final e in _edges) {
        if (e.fromId != id) continue;
        if (!e.condition.isSatisfiedBy(context)) continue;
        if (reached.add(e.toId)) frontier.add(e.toId);
      }
    }
    return reached;
  }

  /// Whether [target] is reachable from [start] following edges structurally
  /// (ignoring conditions) — the cycle test [connect] uses.
  bool _canReach(TransformNodeId start, TransformNodeId target) {
    if (start == target) return true;
    final seen = <TransformNodeId>{start};
    final frontier = <TransformNodeId>[start];
    while (frontier.isNotEmpty) {
      final id = frontier.removeLast();
      for (final e in _edges) {
        if (e.fromId != id) continue;
        if (e.toId == target) return true;
        if (seen.add(e.toId)) frontier.add(e.toId);
      }
    }
    return false;
  }

  void _bump() {
    _version++;
    notifyListeners();
  }
}
