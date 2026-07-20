import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_node_frame.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';

/// Binds one [PatchNode] to a [PatchNodeFrame] plus the registered body
/// builder, and turns a body drag into a single journaled node move (design
/// §6, "click anywhere on a node and move it").
///
/// The node's own [GestureDetector] handles tap (select) and body-drag (move):
/// a drag previews live on the [PatchNode] and commits one command on release.
/// A live GUI body (the slider fader) sits deeper in the tree, so it wins the
/// gesture arena for its own drags — operating a control never drags its node.
/// Output-port presses are detected by the canvas (its hit area spans the whole
/// scene, so a press just past a node's edge still registers), so the node view
/// bails out of a body drag while a cable drag is in flight.
class PatcherNodeView extends StatelessWidget {
  const PatcherNodeView({
    required this.node,
    required this.controller,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// Called when the node is tapped — the canvas selects the node and shows its
  /// reference (design §5, §6).
  final VoidCallback? onTap;

  /// Whether this node is part of the current selection — draws a bright ring.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // A hand-authored descriptor supplies the live GUI body for the seeded
    // demo nodes; a drag-created engine object has none yet (a later epic
    // issue), so its body is empty. Either way the header shows the node's own
    // title and the frame renders — no type is ever an error placeholder.
    final desc = NodeTypeRegistry.instance.find(node.type);
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final inputYs = _portYs(node.inputs);
        final outputYs = _portYs(node.outputs);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // While a cable drag is in flight (started at an output port), the
          // body drag stays inert so the two gestures never fight.
          onPanStart: (_) {
            if (controller.graph.dragSourcePort != null) return;
            controller.beginNodeDrag(node.id);
          },
          onPanUpdate: (d) {
            if (controller.graph.dragSourcePort != null) return;
            controller.dragSelectedBy(d.delta);
          },
          onPanEnd: (_) {
            if (controller.graph.dragSourcePort != null) return;
            controller.endNodeDrag();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (selected)
                Positioned(
                  left: -3,
                  top: -3,
                  right: -3,
                  bottom: -3,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: PhiColors.fg0, width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [
                          BoxShadow(color: PhiColors.line2, blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              PatchNodeFrame(
                title: node.title,
                voice: node.voice,
                armed: node.armed,
                inputPortYs: inputYs,
                outputPortYs: outputYs,
                inputVoices: [for (final p in node.inputs) p.voice],
                outputVoices: [for (final p in node.outputs) p.voice],
                body: Padding(
                  padding: const EdgeInsets.all(8),
                  child:
                      desc?.buildBody(context, node, controller) ??
                      const SizedBox.shrink(),
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
