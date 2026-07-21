import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/tokens/phi_colors.dart';
import '../../../design/tokens/phi_radii.dart';
import '../../../design/tokens/phi_type.dart';
import '../../../design/widgets/midi_graph/transform_graph_canvas_constants.dart';
import '../../../design/widgets/patcher/patch_grid_painter.dart';
import '../../../domain/midi/graph/always_condition.dart';
import '../../../domain/midi/graph/edge_condition.dart';
import '../../../domain/midi/graph/graph_eval_context.dart';
import '../../../domain/midi/graph/runtime_variable_condition.dart';
import '../../../domain/midi/graph/state_match_condition.dart';
import '../../../domain/midi/graph/transform_edge.dart';
import '../../../domain/midi/graph/transform_node_id.dart';
import '../../../domain/runtime/runtime_variable_registry.dart';
import '../../../domain/state_machine/state_graph.dart';
import '../../../engine/state/midi_graph_controller.dart';
import 'transform_edge_layer.dart';
import 'transform_ghost_cable.dart';
import 'transform_graph_node_view.dart';

/// The node-and-cable editor for a [MidiGraphController]'s graph.
///
/// Mirrors `StateCanvas`: a pan/zoom [InteractiveViewer] over a fixed scene
/// holding the grid backdrop, the edge layer, every node, and the in-flight
/// ghost cable. Drag a node's output port onto another node to author an
/// edge; the domain rejects cycles / duplicate pairs / edges into the source,
/// and this surfaces that as a brief banner. Tap a cable to guard it with a
/// condition (unconditional, a state-machine state, or a runtime variable).
///
/// Edges open under [evalContext] and reachable from the source render solid +
/// bright; the rest dim — so the canvas reads as the active subgraph.
class TransformGraphCanvas extends StatefulWidget {
  const TransformGraphCanvas({
    required this.controller,
    required this.evalContext,
    this.stateGraph,
    this.runtimeVariables,
    super.key,
  });

  final MidiGraphController controller;

  /// The live evaluation context (mirroring `StateGraph.activeStateId` and the
  /// runtime registry's values), used to light the active subgraph.
  final GraphEvalContext evalContext;

  /// The state machine, for the condition menu's state list. `null` when no
  /// state machine is wired — the menu then offers only `always` + variables.
  final StateGraph? stateGraph;

  /// The runtime-variable registry, for the condition menu's `var · name =
  /// value` entries (issue #78). `null` when none is wired — the menu then
  /// offers no variable guards.
  final RuntimeVariableRegistry? runtimeVariables;

  @override
  State<TransformGraphCanvas> createState() => _TransformGraphCanvasState();
}

class _TransformGraphCanvasState extends State<TransformGraphCanvas> {
  Offset _cursor = Offset.zero;
  String? _feedback;
  Timer? _feedbackTimer;

  MidiGraphController get _controller => widget.controller;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerMove: (e) => _updateCursor(e.localPosition),
            onPointerHover: (e) => _updateCursor(e.localPosition),
            onPointerUp: (e) => _onPointerUp(e.localPosition),
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _controller,
                _controller.graph,
                widget.stateGraph,
                widget.runtimeVariables,
              ]),
              builder: (context, _) {
                final dragActive = _controller.dragSourceId != null;
                return InteractiveViewer(
                  transformationController: _controller.transform,
                  constrained: false,
                  minScale: 0.25,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  // Freeze pan/zoom while wiring a cable so the canvas doesn't
                  // slide out from under the drag.
                  panEnabled: !dragActive,
                  scaleEnabled: !dragActive,
                  child: _buildScene(),
                );
              },
            ),
          ),
        ),
        if (_feedback != null)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(child: _FeedbackBanner(message: _feedback!)),
          ),
      ],
    );
  }

  Widget _buildScene() {
    final controller = _controller;
    final graph = controller.graph;
    final ctx = widget.evalContext;

    final rects = <TransformNodeId, Rect>{
      TransformNodeId.source: graphNodeRect(controller, TransformNodeId.source),
      for (final n in graph.nodes) n.id: graphNodeRect(controller, n.id),
    };
    final (activeEdges, reachable) = _activeSubgraph(graph.edges, ctx);
    final version = Object.hash(
      graph.version,
      ctx.activeState?.format(),
      _cursor,
    );

    return SizedBox(
      width: TransformGraphCanvasConstants.canvasSize,
      height: TransformGraphCanvasConstants.canvasSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: PatchGridPainter()),
            ),
          ),
          Positioned.fill(
            child: TransformEdgeLayer(
              edges: graph.edges,
              nodeRects: rects,
              activeEdges: activeEdges,
              version: version,
              onEdgeTap: _onEdgeTap,
            ),
          ),
          // The clip-source sentinel node.
          Positioned(
            left: rects[TransformNodeId.source]!.left,
            top: rects[TransformNodeId.source]!.top,
            child: TransformGraphNodeView(
              id: TransformNodeId.source,
              controller: controller,
              onPortDown: _onPortDown,
              sourceNoteCount: graph.source.notes.length,
            ),
          ),
          for (final node in graph.nodes)
            Positioned(
              left: rects[node.id]!.left,
              top: rects[node.id]!.top,
              child: TransformGraphNodeView(
                id: node.id,
                controller: controller,
                node: node,
                open: reachable.contains(node.id),
                onPortDown: _onPortDown,
                onToggle: () =>
                    controller.setActive(node.id, !node.transform.active),
                onRemove: (_) => controller.removeNode(node.id),
              ),
            ),
          if (controller.dragSourceId != null)
            Positioned.fill(
              child: TransformGhostCable(
                source:
                    rects[controller.dragSourceId!]?.centerRight ?? Offset.zero,
                cursor: _cursor,
              ),
            ),
        ],
      ),
    );
  }

  // ─── cable drag ───────────────────────────────────────────────────────────

  void _onPortDown(TransformNodeId from, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    setState(() => _cursor = _controller.transform.toScene(local));
    _controller.beginCableDrag(from);
  }

  void _updateCursor(Offset local) {
    if (_controller.dragSourceId == null) return;
    setState(() => _cursor = _controller.transform.toScene(local));
  }

  void _onPointerUp(Offset local) {
    final from = _controller.dragSourceId;
    if (from == null) return;
    final scene = _controller.transform.toScene(local);
    final target = _findNodeAt(scene);
    if (target != null && target != from) {
      final ok = _controller.connect(from, target);
      if (!ok) _flash(_rejectionReason(from, target));
    }
    _controller.endCableDrag();
  }

  TransformNodeId? _findNodeAt(Offset scene) {
    const pad = TransformGraphCanvasConstants.nodeHitPadding;
    // Real nodes first, then the source sentinel.
    for (final n in _controller.graph.nodes) {
      if (graphNodeRect(_controller, n.id).inflate(pad).contains(scene)) {
        return n.id;
      }
    }
    final src = graphNodeRect(_controller, TransformNodeId.source);
    if (src.inflate(pad).contains(scene)) return TransformNodeId.source;
    return null;
  }

  String _rejectionReason(TransformNodeId from, TransformNodeId to) {
    if (to.isSource) return "can't wire into the source";
    if (_controller.graph.edges.any((e) => e.fromId == from && e.toId == to)) {
      return 'already connected';
    }
    return 'would create a cycle';
  }

  // ─── edge condition menu ────────────────────────────────────────────────

  Future<void> _onEdgeTap(TransformEdge edge, Offset global) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(global, global),
      Offset.zero & overlay.size,
    );
    final states = widget.stateGraph?.states.toList() ?? const [];
    // Every (variable, candidate value) pair is a concrete guard — no free
    // text (issue #78): the registry enumerates exactly what a variable can
    // hold, so the picker can only author a guard the variable can satisfy.
    final variables = widget.runtimeVariables?.variables.toList() ?? const [];
    final choice = await showMenu<Object>(
      context: context,
      position: position,
      color: PhiColors.bg2,
      items: [
        _item('unconditional', const AlwaysCondition()),
        for (final s in states)
          _item('state · ${s.name}', StateMatchCondition(s.address)),
        for (final v in variables)
          for (final value in v.values)
            _item(
              'var · ${v.name} = $value',
              RuntimeVariableCondition(name: v.name, expected: value),
            ),
        const PopupMenuDivider(),
        _item('disconnect', const _Disconnect()),
      ],
    );
    if (choice == null || !mounted) return;
    _applyChoice(edge, choice);
  }

  void _applyChoice(TransformEdge edge, Object choice) {
    if (choice is EdgeCondition) {
      _controller.setEdgeCondition(edge.fromId, edge.toId, choice);
    } else if (choice is _Disconnect) {
      _controller.disconnect(edge.fromId, edge.toId);
    }
  }

  PopupMenuItem<Object> _item(String label, Object value) {
    return PopupMenuItem<Object>(
      value: value,
      height: 32,
      child: Text(
        label,
        style: PhiType.monoS().copyWith(fontSize: 11, color: PhiColors.fg0),
      ),
    );
  }

  // ─── feedback ─────────────────────────────────────────────────────────────

  void _flash(String message) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  /// The set of edges carrying notes and the set of nodes reachable from the
  /// source under [ctx] — the active subgraph. BFS following only open edges.
  (Set<TransformEdge>, Set<TransformNodeId>) _activeSubgraph(
    List<TransformEdge> edges,
    GraphEvalContext ctx,
  ) {
    final openEdges = <TransformEdge>{};
    final reached = <TransformNodeId>{TransformNodeId.source};
    final frontier = <TransformNodeId>[TransformNodeId.source];
    while (frontier.isNotEmpty) {
      final id = frontier.removeLast();
      for (final e in edges) {
        if (e.fromId != id) continue;
        if (!e.condition.isSatisfiedBy(ctx)) continue;
        openEdges.add(e);
        if (reached.add(e.toId)) frontier.add(e.toId);
      }
    }
    return (openEdges, reached);
  }
}

/// Menu sentinel: remove the edge.
class _Disconnect {
  const _Disconnect();
}

/// Transient banner for a rejected edge.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        border: Border.all(color: PhiColors.hot.withValues(alpha: 0.6)),
        borderRadius: PhiRadii.all2,
      ),
      child: Text(
        'edge rejected · $message'.toUpperCase(),
        style: PhiType.caption().copyWith(color: PhiColors.hot),
      ),
    );
  }
}
