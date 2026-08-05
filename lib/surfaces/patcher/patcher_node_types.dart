import 'package:flutter/widgets.dart';
import 'package:yse/yse.dart';

import '../../domain/patcher/patch_port_kind.dart';
import '../../engine/state/node_type_registry.dart';
import 'nodes/button_node_body.dart';
import 'nodes/message_node_body.dart';
import 'nodes/number_node_body.dart';
import 'nodes/sine_node_body.dart';
import 'nodes/slider_node_body.dart';
import 'nodes/toggle_node_body.dart';

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
      // Its freq readout is the object's live `guiValue`, so a cable into the
      // freq inlet has to reach the display (issue #357).
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gSlider,
      title: 'slider',
      // Tall enough to seat the fader plus its `guiValue` readout (issue #223).
      defaultSize: const Size(90, 190),
      // gSlider registers no `ADD_PARAM` in its C++ constructor, so the
      // YSE parameter parser dereferences an empty vector if we pass any
      // args here — segfault. Leave empty.
      defaultArgs: '',
      inputs: const [],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          SliderNodeBody(node: node, controller: controller),
      readsGuiValue: true,
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

  // ─── live GUI bodies (issue #223) ──────────────────────────────────────
  // Interactive control objects operable directly on the canvas — in **run**
  // mode, which is where a body answers a press at all (issue #378). Each
  // writes through the gateway (`sendFloat` / `sendBang`) and displays via
  // `guiValue`.

  registry.register(
    NodeDescriptor(
      type: Obj.gToggle,
      title: 'toggle',
      defaultSize: const Size(90, 80),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          ToggleNodeBody(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gButton,
      title: 'button',
      defaultSize: const Size(90, 90),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          ButtonNodeBody(node: node, controller: controller),
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gFloat,
      title: 'number · f',
      defaultSize: const Size(110, 70),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          NumberNodeBody(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gInt,
      title: 'number · i',
      defaultSize: const Size(110, 70),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          NumberNodeBody(node: node, controller: controller, integer: true),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gMessage,
      title: 'message',
      defaultSize: const Size(120, 66),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          MessageNodeBody(node: node, controller: controller),
    ),
  );
}
