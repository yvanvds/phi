import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_gui_object.dart';
import '../../design/widgets/patcher/patch_object_box.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../domain/patcher/patch_type_name.dart';
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';

/// Binds one [PatchNode] to the chrome its kind gets (design §6, "click
/// anywhere on a node and move it").
///
/// Two kinds, and the descriptor decides (design §7, §12.2). Every engine object
/// is a [PatchObjectBox] — one bordered line reading `sine 440` in the DSP blue,
/// no header, no drawn `~`/`.` prefix (issues #379, #380). A type with a
/// hand-authored GUI body is a [PatchGuiObject]: the control itself, filling the
/// node, with nothing around it but its ports (issue #381). **There are no
/// headers left anywhere** — which is why `PatchNode` no longer carries a
/// display title at all.
///
/// **Purely visual** where pointers are concerned: select, double-click and
/// body-drag are all driven by the canvas's raw pointer pipeline, which sees
/// every press over the scene and can therefore track the pointer 1:1 without
/// a gesture recogniser's slop being discarded first (issue #352). Adding a
/// [GestureDetector] here would put the node back in the arena and reintroduce
/// exactly that lag.
///
/// Whether a live GUI body (fader, number field, message box) answers a press
/// at all is the canvas's **mode**, not the node's type (issue #378): with the
/// header gone there is no neutral chrome left to drag a fader by, so in edit
/// mode every body is switched off here and the canvas drags the node from
/// anywhere on it. In run mode the bodies are live and own every press — they
/// sit deeper in the tree, and the canvas starts no gesture of its own.
class PatcherNodeView extends StatelessWidget {
  const PatcherNodeView({
    required this.node,
    required this.controller,
    this.selected = false,
    this.bodyLive = false,
    super.key,
  });

  final PatchNode node;
  final PatcherController controller;

  /// Whether this node is part of the current selection — draws a bright ring.
  final bool selected;

  /// Whether the body takes pointers — true only in run mode (issue #378).
  ///
  /// Switched off with an [IgnorePointer] rather than by handing each body an
  /// "inert" flag of its own: the rule is the canvas's, it must hold for every
  /// body ever registered, and a body that has to remember to obey it is a body
  /// that will one day forget.
  final bool bodyLive;

  /// Key on one node's rendered object-box line, so a test can name the text of
  /// a specific node on a canvas full of them.
  static Key objectLineKey(PatchNodeId id) => Key('PatchObjectBox.${id.value}');

  @override
  Widget build(BuildContext context) {
    // A hand-authored descriptor supplies the live GUI body for the types that
    // have one; every other engine object is an object box printing what it
    // actually is — `~sine 440` — instead of a header saying it twice over an
    // empty body (issue #379). No type is ever an error placeholder.
    final body = NodeTypeRegistry.instance.find(node.type)?.buildBody;
    return ListenableBuilder(
      listenable: node,
      builder: (context, _) {
        final inputXs = _portXs(node.inputs);
        final outputXs = _portXs(node.outputs);
        final inputVoices = [for (final p in node.inputs) p.voice];
        final outputVoices = [for (final p in node.outputs) p.voice];
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
            if (body == null)
              PatchObjectBox(
                text: controller.objectLineOf(node.id),
                // The `~`/`.` the line no longer prints, as its colour
                // (issue #380) — read off the canonical type id, which is what
                // the node has always been keyed by.
                isDsp: PatchTypeName.isDsp(node.type),
                textKey: objectLineKey(node.id),
                voice: node.voice,
                armed: node.armed,
                inputPortXs: inputXs,
                outputPortXs: outputXs,
                inputVoices: inputVoices,
                outputVoices: outputVoices,
              )
            else
              PatchGuiObject(
                voice: node.voice,
                armed: node.armed,
                inputPortXs: inputXs,
                outputPortXs: outputXs,
                inputVoices: inputVoices,
                outputVoices: outputVoices,
                // No padding: the control *is* the node, so it takes the whole
                // rectangle the canvas laid out for it (issue #381).
                child: IgnorePointer(
                  ignoring: !bodyLive,
                  child: body(context, node, controller),
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
