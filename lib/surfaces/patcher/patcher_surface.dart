import 'package:flutter/widgets.dart';
import 'package:yse/yse.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../engine/engine.dart';
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';
import '../surface.dart';
import 'patcher_canvas.dart';
import 'patcher_node_types.dart';

/// Patcher surface — pan/zoom canvas of nodes and cables.
///
/// Requires the engine to be started: the [PatcherController] is created
/// in [PhiEngine.start] and torn down in `stop`. Before start the surface
/// renders a low-key placeholder.
class PatcherSurface extends Surface {
  const PatcherSurface({required this.engine, super.key});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.bg0,
      child: engine.patcherOrNull != null
          ? _PatcherViewport(engine: engine)
          : const _Offline(),
    );
  }
}

/// Inner widget that owns the one-shot seeding of the default graph.
///
/// Kept separate so the seed runs once on first mount, not on every
/// Flutter rebuild of the surrounding chrome.
class _PatcherViewport extends StatefulWidget {
  const _PatcherViewport({required this.engine});

  final PhiEngine engine;

  @override
  State<_PatcherViewport> createState() => _PatcherViewportState();
}

class _PatcherViewportState extends State<_PatcherViewport> {
  @override
  void initState() {
    super.initState();
    registerBuiltInPatcherNodes();
    _seedDefaultGraphIfEmpty(widget.engine.patcher);
  }

  void _seedDefaultGraphIfEmpty(PatcherController controller) {
    if (controller.graph.nodes.isNotEmpty) return;
    final registry = NodeTypeRegistry.instance;
    // Note: gSlider outputs raw [0, 1] and `~sine` reads inlet[0] as a
    // frequency in Hz, so the slider's range only sweeps 0–1 Hz here —
    // sub-audible. A math-node mapping arrives in a follow-up; for now
    // the demo proves the architecture, not the musicality.
    final slider = controller.addNode(
      desc: registry.find(Obj.gSlider)!,
      position: const Offset(120, 180),
      voice: 1,
    );
    final sine = controller.addNode(
      desc: registry.find(Obj.dSine)!,
      position: const Offset(280, 220),
      voice: 2,
    );
    final dac = controller.addNode(
      desc: registry.find(Obj.dDac)!,
      position: const Offset(500, 240),
      voice: 3,
    );
    controller.connect(
      _portId(slider.id, PatchPortSide.output, 0),
      _portId(sine.id, PatchPortSide.input, 0),
    );
    controller.connect(
      _portId(sine.id, PatchPortSide.output, 0),
      _portId(dac.id, PatchPortSide.input, 0),
    );
    // Now that the patcher has a `~dac`, it's safe to bind a Sound to it.
    controller.mountAudio();
  }

  PatchPortId _portId(PatchNodeId id, PatchPortSide side, int index) =>
      PatchPortId(nodeId: id, side: side, index: index);

  @override
  Widget build(BuildContext context) =>
      PatcherCanvas(controller: widget.engine.patcher);
}

class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'patcher offline · start the engine'.toUpperCase(),
        style: PhiType.caption(),
      ),
    );
  }
}
