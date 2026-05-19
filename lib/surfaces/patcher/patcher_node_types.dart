import 'package:flutter/widgets.dart';
import 'package:yse/yse.dart';

import '../../domain/patcher/patch_port_kind.dart';
import '../../engine/state/node_type_registry.dart';
import 'nodes/sine_node_body.dart';
import 'nodes/slider_node_body.dart';

/// Register the node types this PR supports. Idempotent — re-registering
/// the same type overwrites the previous descriptor, so calling this
/// from `PatcherSurface.initState` (or `main.dart`) on every rebuild is
/// safe.
///
/// Adding a new node type = one extra body file under `nodes/` + one
/// extra `register(...)` block here. The canvas code is closed against
/// the set.
void registerBuiltInPatcherNodes() {
  final registry = NodeTypeRegistry.instance;

  registry.register(
    NodeDescriptor(
      type: Obj.dSine,
      title: 'osc · sine',
      defaultSize: const Size(130, 70),
      defaultArgs: '440',
      inputs: const [PortSpec(kind: PatchPortKind.control, label: 'freq')],
      outputs: const [PortSpec(kind: PatchPortKind.audio)],
      buildBody: (ctx, node, controller) =>
          SineNodeBody(node: node, controller: controller),
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gSlider,
      title: 'slider',
      defaultSize: const Size(80, 170),
      // gSlider registers no `ADD_PARAM` in its C++ constructor, so the
      // YSE parameter parser dereferences an empty vector if we pass any
      // args here — segfault. Leave empty.
      defaultArgs: '',
      inputs: const [],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          SliderNodeBody(node: node, controller: controller),
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.dDac,
      title: 'out · L/R',
      defaultSize: const Size(110, 60),
      defaultArgs: '',
      inputs: const [
        PortSpec(kind: PatchPortKind.audio, label: 'L'),
        PortSpec(kind: PatchPortKind.audio, label: 'R'),
      ],
      outputs: const [],
      buildBody: (ctx, node, controller) => const SizedBox.shrink(),
    ),
  );
}
