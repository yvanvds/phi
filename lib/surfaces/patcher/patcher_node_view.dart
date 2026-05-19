import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_node_frame.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';

/// Binds one [PatchNode] to a [PatchNodeFrame] plus the registered body
/// builder, and translates pointer drags into `controller.moveNode`.
///
/// Output ports are wrapped in [Listener] so they claim pointer-downs
/// before any enclosing gesture recogniser — used by the canvas to start
/// a cable-drag without competing with the node-move gesture.
class PatcherNodeView extends StatelessWidget {
  const PatcherNodeView({
    required this.node,
    required this.controller,
    required this.onOutputPortDown,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// Called when the user presses on one of this node's output port dots.
  /// The canvas uses this to start a drag-to-create-cable gesture.
  final void Function(PatchPortId portId, Offset globalPosition)
  onOutputPortDown;

  @override
  Widget build(BuildContext context) {
    final desc = NodeTypeRegistry.instance.find(node.type);
    if (desc == null) {
      // Unknown type — render a minimal placeholder so the canvas does
      // not blow up. Adding a registry entry will replace this.
      return const _UnknownNodePlaceholder();
    }
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final inputYs = _portYs(node.inputs);
        final outputYs = _portYs(node.outputs);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => controller.moveNode(node.id, d.delta),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PatchNodeFrame(
                title: desc.title,
                voice: node.voice,
                armed: node.armed,
                inputPortYs: inputYs,
                outputPortYs: outputYs,
                inputVoices: [for (final p in node.inputs) p.voice],
                outputVoices: [for (final p in node.outputs) p.voice],
                body: Padding(
                  padding: const EdgeInsets.all(8),
                  child: desc.buildBody(context, node, controller),
                ),
              ),
              for (var i = 0; i < node.outputs.length; i++)
                Positioned(
                  right:
                      -PatchCanvasConstants.portDotRadius -
                      PatchCanvasConstants.portHitRadius / 2,
                  top: outputYs[i] - PatchCanvasConstants.portHitRadius / 2,
                  width: PatchCanvasConstants.portHitRadius,
                  height: PatchCanvasConstants.portHitRadius,
                  // Invisible hit-target overlaying the frame's port dot —
                  // claims pointer-downs to start a cable drag without
                  // double-drawing the visible dot.
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) => onOutputPortDown(
                      PatchPortId(
                        nodeId: node.id,
                        side: PatchPortSide.output,
                        index: i,
                      ),
                      e.position,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static List<double> _portYs(List<PatchPort> ports) {
    return [
      for (var i = 0; i < ports.length; i++)
        PatchCanvasConstants.headerHeight +
            PatchCanvasConstants.firstPortOffset +
            i * PatchCanvasConstants.portSpacing,
    ];
  }
}

/// Compute canvas-local port centres for a node — used by the canvas to
/// build the `Map<PatchPortId, Offset>` the cable painter consumes.
Map<PatchPortId, Offset> portPositionsFor(PatchNode node) {
  final out = <PatchPortId, Offset>{};
  final origin = node.position;
  final size = node.size;
  for (var i = 0; i < node.inputs.length; i++) {
    out[PatchPortId(
      nodeId: node.id,
      side: PatchPortSide.input,
      index: i,
    )] = Offset(
      origin.dx,
      origin.dy +
          PatchCanvasConstants.headerHeight +
          PatchCanvasConstants.firstPortOffset +
          i * PatchCanvasConstants.portSpacing,
    );
  }
  for (var i = 0; i < node.outputs.length; i++) {
    out[PatchPortId(
      nodeId: node.id,
      side: PatchPortSide.output,
      index: i,
    )] = Offset(
      origin.dx + size.width,
      origin.dy +
          PatchCanvasConstants.headerHeight +
          PatchCanvasConstants.firstPortOffset +
          i * PatchCanvasConstants.portSpacing,
    );
  }
  return out;
}

class _UnknownNodePlaceholder extends StatelessWidget {
  const _UnknownNodePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0x33FF0000)),
      child: SizedBox(width: 80, height: 40),
    );
  }
}
