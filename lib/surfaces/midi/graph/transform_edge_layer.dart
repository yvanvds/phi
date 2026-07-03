import 'package:flutter/widgets.dart';

import '../../../design/widgets/midi_graph/transform_edge_geometry.dart';
import '../../../design/widgets/midi_graph/transform_edge_painter.dart';
import '../../../design/widgets/midi_graph/transform_graph_canvas_constants.dart';
import '../../../domain/midi/graph/transform_edge.dart';
import '../../../domain/midi/graph/transform_node_id.dart';

/// Wraps [TransformEdgePainter] in a `GestureDetector` that maps a tap onto
/// the nearest cable, so the canvas can open its condition menu. The painter
/// itself stays input-unaware.
///
/// Hit-testing samples each edge's cubic and picks the closest within
/// [TransformGraphCanvasConstants.edgeHitThreshold] canvas-local pixels; misses
/// fall through so node drags in the gaps aren't intercepted.
class TransformEdgeLayer extends StatelessWidget {
  const TransformEdgeLayer({
    required this.edges,
    required this.nodeRects,
    required this.activeEdges,
    required this.version,
    this.onEdgeTap,
    super.key,
  });

  final List<TransformEdge> edges;
  final Map<TransformNodeId, Rect> nodeRects;
  final Set<TransformEdge> activeEdges;
  final int version;

  /// Called with the tapped edge and the global tap position (so the canvas can
  /// anchor a popup menu). `null` makes the layer non-interactive.
  final void Function(TransformEdge edge, Offset globalPosition)? onEdgeTap;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      painter: TransformEdgePainter(
        edges: edges,
        nodeRects: nodeRects,
        activeEdges: activeEdges,
        version: version,
      ),
      child: const SizedBox.expand(),
    );
    if (onEdgeTap == null) {
      return IgnorePointer(child: paint);
    }
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTapUp: (d) {
        final hit = _hitTest(d.localPosition);
        if (hit != null) onEdgeTap!(hit, d.globalPosition);
      },
      child: paint,
    );
  }

  TransformEdge? _hitTest(Offset local) {
    TransformEdge? best;
    var bestDistance = TransformGraphCanvasConstants.edgeHitThreshold;
    for (final e in edges) {
      final src = nodeRects[e.fromId];
      final dst = nodeRects[e.toId];
      if (src == null || dst == null) continue;
      final curve = TransformEdgeGeometry.curveBetween(src, dst);
      final d = TransformEdgeGeometry.distanceTo(curve, local);
      if (d < bestDistance) {
        bestDistance = d;
        best = e;
      }
    }
    return best;
  }
}
