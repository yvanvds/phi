import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_grid_painter.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../domain/patcher/patch_port_kind.dart';
import '../../engine/state/patcher_controller.dart';
import 'patcher_cable_layer.dart';
import 'patcher_ghost_cable.dart';
import 'patcher_node_view.dart';

/// The pan/zoom canvas itself. Hosts the grid backdrop, the cable layer,
/// every [PatchNode]'s widget, and the in-flight ghost cable. Tracks the
/// cursor's canvas-local position so the ghost cable can follow it.
class PatcherCanvas extends StatefulWidget {
  const PatcherCanvas({required this.controller, super.key});

  final PatcherController controller;

  @override
  State<PatcherCanvas> createState() => _PatcherCanvasState();
}

class _PatcherCanvasState extends State<PatcherCanvas> {
  Offset _cursor = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Listener(
      onPointerMove: (e) => _updateCursor(e.localPosition),
      onPointerHover: (e) => _updateCursor(e.localPosition),
      onPointerUp: (e) => _onPointerUp(e.localPosition),
      child: InteractiveViewer(
        transformationController: controller.transform,
        constrained: false,
        minScale: 0.25,
        maxScale: 4.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: SizedBox(
          width: PatchCanvasConstants.canvasSize,
          height: PatchCanvasConstants.canvasSize,
          child: ListenableBuilder(
            listenable: controller.graph,
            builder: (context, _) {
              final graph = controller.graph;
              final positions = <PatchPortId, Offset>{};
              final voiceForSource = <PatchPortId, int>{};
              for (final n in graph.nodes) {
                positions.addAll(portPositionsFor(n));
                for (var i = 0; i < n.outputs.length; i++) {
                  voiceForSource[PatchPortId(
                        nodeId: n.id,
                        side: PatchPortSide.output,
                        index: i,
                      )] =
                      n.outputs[i].voice;
                }
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: PatchGridPainter()),
                    ),
                  ),
                  Positioned.fill(
                    child: PatcherCableLayer(
                      cables: graph.cables,
                      portPositions: positions,
                      cableVoiceForSource: voiceForSource,
                      version: graph.version,
                    ),
                  ),
                  for (final n in graph.nodes)
                    Positioned(
                      left: n.position.dx,
                      top: n.position.dy,
                      width: n.size.width,
                      height: n.size.height,
                      child: PatcherNodeView(
                        node: n,
                        controller: controller,
                        onOutputPortDown: _onOutputPortDown,
                      ),
                    ),
                  if (graph.dragSourcePort != null)
                    Positioned.fill(
                      child: PatcherGhostCable(
                        source: positions[graph.dragSourcePort!] ?? Offset.zero,
                        cursor: _cursor,
                        voice: voiceForSource[graph.dragSourcePort!] ?? 1,
                        kind: _kindForSource(graph.dragSourcePort!),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _updateCursor(Offset local) {
    if (widget.controller.graph.dragSourcePort == null) return;
    setState(() => _cursor = local);
  }

  void _onOutputPortDown(PatchPortId portId, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    setState(() => _cursor = local);
    widget.controller.beginCableDrag(portId);
  }

  void _onPointerUp(Offset local) {
    final source = widget.controller.graph.dragSourcePort;
    if (source == null) return;
    final hit = _findInputPortAt(local);
    if (hit != null) {
      widget.controller.connect(source, hit);
    }
    widget.controller.endCableDrag();
  }

  PatchPortId? _findInputPortAt(Offset local) {
    final controller = widget.controller;
    const hitR = PatchCanvasConstants.portHitRadius;
    for (final n in controller.graph.nodes) {
      final positions = portPositionsFor(n);
      for (var i = 0; i < n.inputs.length; i++) {
        final pos =
            positions[PatchPortId(
              nodeId: n.id,
              side: PatchPortSide.input,
              index: i,
            )];
        if (pos == null) continue;
        if ((pos - local).distance <= hitR) {
          return PatchPortId(nodeId: n.id, side: PatchPortSide.input, index: i);
        }
      }
    }
    return null;
  }

  PatchPortKind _kindForSource(PatchPortId portId) {
    final node = widget.controller.graph.nodeById(portId.nodeId);
    if (node == null || portId.index >= node.outputs.length) {
      return PatchPortKind.control;
    }
    return node.outputs[portId.index].kind;
  }
}
