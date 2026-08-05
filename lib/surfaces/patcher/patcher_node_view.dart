import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_node_frame.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';
import 'nodes/patch_args_body.dart';

/// Binds one [PatchNode] to a [PatchNodeFrame] plus the registered body
/// builder (design §6, "click anywhere on a node and move it").
///
/// **Purely visual** where pointers are concerned: select, double-click and
/// body-drag are all driven by the canvas's raw pointer pipeline, which sees
/// every press over the scene and can therefore track the pointer 1:1 without
/// a gesture recogniser's slop being discarded first (issue #352). Adding a
/// [GestureDetector] here would put the node back in the arena and reintroduce
/// exactly that lag.
///
/// A live GUI body (fader, number field, message box) still owns its own
/// gestures — it sits deeper in the tree and the canvas deliberately ignores
/// presses that land inside a body whose descriptor is
/// [NodeDescriptor.interactiveBody].
class PatcherNodeView extends StatelessWidget {
  const PatcherNodeView({
    required this.node,
    required this.controller,
    this.selected = false,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// Whether this node is part of the current selection — draws a bright ring.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // A hand-authored descriptor supplies the live GUI body for the types that
    // have one; every other engine object falls back to [PatchArgsBody], which
    // prints what the object actually is — `~sine 440` — instead of the empty
    // box a drag-created node used to render (issue #356). Either way the
    // header shows the node's own title and the frame renders — no type is ever
    // an error placeholder.
    final desc = NodeTypeRegistry.instance.find(node.type);
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final inputXs = _portXs(node.inputs);
        final outputXs = _portXs(node.outputs);
        return Stack(
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
              inputPortXs: inputXs,
              outputPortXs: outputXs,
              inputVoices: [for (final p in node.inputs) p.voice],
              outputVoices: [for (final p in node.outputs) p.voice],
              body: Padding(
                padding: const EdgeInsets.all(8),
                child:
                    desc?.buildBody(context, node, controller) ??
                    PatchArgsBody(node: node, controller: controller),
              ),
            ),
          ],
        );
      },
    );
  }

  static List<double> _portXs(List<PatchPort> ports) => [
    for (var i = 0; i < ports.length; i++) patchPortOffsetAlongEdge(i),
  ];
}

/// Distance from a node's left edge to the centre of its port number [index],
/// on either horizontal edge (design §6, issue #377).
///
/// The one place the spread is expressed: the frame draws its dots at these
/// offsets, [portPositionsFor] resolves the same offsets into scene space for
/// the cables and the hit-tests, and
/// [PatchCanvasConstants.minWidthForPorts] is the width that keeps the last of
/// them inside the box.
double patchPortOffsetAlongEdge(int index) =>
    PatchCanvasConstants.firstPortOffset +
    index * PatchCanvasConstants.portSpacing;

/// Compute canvas-local port centres for a node — used by the canvas to
/// build the `Map<PatchPortId, Offset>` the cable painter consumes.
///
/// Inlets sit on the node's **top** edge and outlets on its **bottom** one, so
/// a cable drops out of one box and into the next (design §6).
Map<PatchPortId, Offset> portPositionsFor(PatchNode node) {
  final out = <PatchPortId, Offset>{};
  final origin = node.position;
  final size = node.size;
  for (var i = 0; i < node.inputs.length; i++) {
    out[PatchPortId(nodeId: node.id, side: PatchPortSide.input, index: i)] =
        Offset(origin.dx + patchPortOffsetAlongEdge(i), origin.dy);
  }
  for (var i = 0; i < node.outputs.length; i++) {
    out[PatchPortId(
      nodeId: node.id,
      side: PatchPortSide.output,
      index: i,
    )] = Offset(
      origin.dx + patchPortOffsetAlongEdge(i),
      origin.dy + size.height,
    );
  }
  return out;
}
