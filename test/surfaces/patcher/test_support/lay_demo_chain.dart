import 'package:flutter/painting.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_node_id.dart';
import 'package:phi/domain/patcher/patch_object_types.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';

/// Lays the `.slider → ~sine → ~dac` chain into [controller] — a test
/// fixture, at the positions and with the voices the Patcher surface's old
/// first-visit demo seed used, so tests written against that seed keep their
/// geometry.
///
/// The surface no longer seeds an empty patch (issue #523): a project opens
/// with every patch empty and stopped. Like the old seed this uses the
/// non-journaled [PatcherController.addNode] / [PatcherController.connect]
/// primitives, but it does **not** mount the patch on a bus — a test that
/// wants it audible calls [PatcherController.mountAudio] itself.
///
/// Returns the three nodes in chain order. Call it after the surface is up
/// (it registers the built-in node types).
({PatchNode slider, PatchNode sine, PatchNode dac}) layDemoChain(
  PatcherController controller,
) {
  final registry = NodeTypeRegistry.instance;
  final slider = controller.addNode(
    desc: registry.find(PatchObjectTypes.gSlider)!,
    position: const Offset(120, 180),
    voice: 1,
  );
  final sine = controller.addNode(
    desc: registry.find(PatchObjectTypes.dSine)!,
    position: const Offset(280, 220),
    voice: 2,
  );
  final dac = controller.addNode(
    desc: registry.find(PatchObjectTypes.dDac)!,
    position: const Offset(500, 240),
    voice: 3,
  );
  PatchPortId port(PatchNodeId id, PatchPortSide side) =>
      PatchPortId(nodeId: id, side: side, index: 0);
  controller.connect(
    port(slider.id, PatchPortSide.output),
    port(sine.id, PatchPortSide.input),
  );
  controller.connect(
    port(sine.id, PatchPortSide.output),
    port(dac.id, PatchPortSide.input),
  );
  return (slider: slider, sine: sine, dac: dac);
}
