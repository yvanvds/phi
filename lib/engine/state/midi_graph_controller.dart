import 'package:flutter/widgets.dart';

import '../../design/widgets/midi_graph/transform_graph_canvas_constants.dart';
import '../../domain/midi/graph/always_condition.dart';
import '../../domain/midi/graph/edge_condition.dart';
import '../../domain/midi/graph/midi_transform_graph.dart';
import '../../domain/midi/graph/transform_node.dart';
import '../../domain/midi/graph/transform_node_id.dart';
import '../../domain/midi/midi_clip_mode.dart';
import '../../domain/midi/midi_transform.dart';
import '../../domain/midi/midi_transform_chain.dart';

/// Engine-side mediator between canvas gestures and a [MidiTransformGraph].
///
/// Mirrors [StateMachineController]: pure Dart (the transform graph has no
/// native counterpart), owning the domain graph plus the [TransformationController]
/// for pan/zoom. The one addition is **layout** — the domain graph is
/// deliberately position-free, so node canvas coordinates (including the
/// source sentinel's) live here in [_positions], snapped to the 16px grid.
///
/// A [ChangeNotifier] so the canvas can react to position + drag changes
/// (which don't touch the domain graph); structural changes come through
/// [graph] as usual. The canvas listens to both.
class MidiGraphController extends ChangeNotifier {
  MidiGraphController({
    required this.graph,
    Map<TransformNodeId, Offset>? positions,
  }) : _positions = positions ?? <TransformNodeId, Offset>{};

  /// Build a graph mirroring [chain] — `source → t0 → t1 → …` with
  /// unconditional edges, laid out left-to-right — so the graph opens on the
  /// working linear chain the performer then re-wires into branches. Shares
  /// [chain]'s source clip, so piano-roll edits flow into `evaluate`.
  factory MidiGraphController.seededFrom(MidiTransformChain chain) {
    final graph = MidiTransformGraph(source: chain.source);
    final positions = <TransformNodeId, Offset>{
      TransformNodeId.source: _origin,
    };
    var previous = TransformNodeId.source;
    var column = 1;
    for (final transform in chain.transforms) {
      final node = graph.addNode(transform);
      graph.connect(previous, node.id);
      positions[node.id] = Offset(
        _origin.dx + column * _columnSpacing,
        _origin.dy,
      );
      previous = node.id;
      column++;
    }
    return MidiGraphController(graph: graph, positions: positions);
  }

  /// The domain graph. Listen for add/remove/connect/condition changes.
  final MidiTransformGraph graph;

  /// Pan/zoom state for the canvas [InteractiveViewer].
  final TransformationController transform = TransformationController();

  MidiClipMode _mode = MidiClipMode.chain;

  /// Which representation the clip is in — the linear chain or the branching
  /// graph. The MIDI surface binds its view to this (chain editor vs canvas),
  /// and the engine player reads it each tick to decide whether playback comes
  /// from `chain.output` or `graph.evaluate(context)`. In the running app the
  /// surface and player hold the *same* controller, so the view the performer
  /// sees and the pipeline they hear never drift.
  MidiClipMode get mode => _mode;
  set mode(MidiClipMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
  }

  final Map<TransformNodeId, Offset> _positions;
  TransformNodeId? _dragSourceId;

  /// The node a drag-to-connect gesture started from, if one is in flight.
  TransformNodeId? get dragSourceId => _dragSourceId;

  /// Canvas-local top-left of [id]'s node box. Falls back to [_origin] for an
  /// id with no recorded position (defensive — every added node gets one).
  Offset positionOf(TransformNodeId id) => _positions[id] ?? _origin;

  // ─── node lifecycle ─────────────────────────────────────────────────────

  /// Add a node wrapping [transform] at [position] (snapped) and return it.
  TransformNode addNodeAt(MidiTransform transform, Offset position) {
    final node = graph.addNode(transform); // graph notifies
    _positions[node.id] = _snap(position);
    return node;
  }

  /// Remove [id] and its recorded position (and, via the graph, its edges).
  void removeNode(TransformNodeId id) {
    _positions.remove(id);
    graph.removeNode(id); // graph notifies
  }

  /// Move [id]'s node by [delta] (canvas-local pixels), snapped to the grid.
  void moveNode(TransformNodeId id, Offset delta) {
    final current = _positions[id];
    if (current == null) return;
    _positions[id] = _snap(current + delta);
    notifyListeners();
  }

  // ─── edge lifecycle ─────────────────────────────────────────────────────

  /// Connect [from] → [to] under [condition]. Returns whether the edge was
  /// made — `false` on a cycle, a duplicate pair, or a target of the source
  /// sentinel (the domain rejects these; the canvas surfaces the rejection).
  bool connect(
    TransformNodeId from,
    TransformNodeId to, {
    EdgeCondition condition = const AlwaysCondition(),
  }) => graph.connect(from, to, condition: condition);

  /// Remove the `(from, to)` edge whatever its condition.
  void disconnect(TransformNodeId from, TransformNodeId to) =>
      graph.disconnect(from, to);

  /// Replace the guard on an existing `(from, to)` edge. Removes and re-adds it
  /// under [condition]; returns whether such an edge existed (the re-add always
  /// succeeds because the pair was already valid).
  bool setEdgeCondition(
    TransformNodeId from,
    TransformNodeId to,
    EdgeCondition condition,
  ) {
    final exists = graph.edges.any((e) => e.fromId == from && e.toId == to);
    if (!exists) return false;
    graph.disconnect(from, to);
    return graph.connect(from, to, condition: condition);
  }

  /// Toggle the `active` flag on [id]'s transform.
  void setActive(TransformNodeId id, bool active) =>
      graph.setActive(id, active);

  // ─── drag-to-connect ────────────────────────────────────────────────────

  void beginCableDrag(TransformNodeId from) {
    _dragSourceId = from;
    notifyListeners();
  }

  void endCableDrag() {
    if (_dragSourceId == null) return;
    _dragSourceId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    transform.dispose();
    graph.dispose();
    super.dispose();
  }

  static const Offset _origin = Offset(160, 240);
  static const double _columnSpacing = 190;

  static Offset _snap(Offset p) {
    const step = TransformGraphCanvasConstants.snapStep;
    return Offset(
      (p.dx / step).roundToDouble() * step,
      (p.dy / step).roundToDouble() * step,
    );
  }
}
