import 'package:flutter/widgets.dart';
import 'package:yse/yse.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_object_box_metrics.dart';
import '../../domain/patcher/patch_port_kind.dart';
import '../../engine/state/node_type_registry.dart';
import 'nodes/button_node_body.dart';
import 'nodes/message_node_body.dart';
import 'nodes/number_node_body.dart';
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
  const square = PatchCanvasConstants.guiControlMinSize;
  final lineHeight = _guiLineBoxHeight();

  // ─── object boxes (issue #379) ─────────────────────────────────────────
  // Registered for their creation args and documented port shapes only: with
  // no `buildBody` they render as object boxes — one bordered line reading
  // `~sine 440` — so they carry neither a title nor a tuned size, and the
  // controller measures their box from that line.

  registry.register(
    const NodeDescriptor(
      type: Obj.dSine,
      defaultArgs: '440',
      inputs: [PortSpec(kind: PatchPortKind.control, label: 'freq')],
      outputs: [PortSpec(kind: PatchPortKind.audio)],
    ),
  );

  registry.register(
    NodeDescriptor(
      type: Obj.gSlider,
      // A bare fader and nothing else (issue #381): as wide as the track plus
      // its thumb overhang, floored by the port geometry, and a Max-ish throw
      // tall. No header, no readout, so no rows to seat.
      defaultSize: const Size(square + 4, 140),
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
    const NodeDescriptor(
      type: Obj.dDac,
      defaultArgs: '',
      inputs: [
        PortSpec(kind: PatchPortKind.audio, label: 'L'),
        PortSpec(kind: PatchPortKind.audio, label: 'R'),
      ],
      outputs: [],
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
      // The switch itself — a square with a cross in it (issue #381).
      defaultSize: const Size(square, square),
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
      // The bang square itself — no frame, no `bang` caption (issue #381).
      defaultSize: const Size(square, square),
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
      // A bare readout, one line tall like an object box (issue #381).
      defaultSize: Size(_numberBoxWidth, lineHeight),
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
      defaultSize: Size(_numberBoxWidth, lineHeight),
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
      // The message box itself, one line tall — its notched right edge is what
      // tells it from a number box now (issue #381).
      defaultSize: Size(_messageBoxWidth, lineHeight),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          MessageNodeBody(node: node, controller: controller),
    ),
  );
}

/// Width a bare number box opens at — room for a few digits and their sign
/// before the cut corner, and no more: a readout that says `0.5` has no use for
/// the 110px the old `NUMBER · F` frame spent (issue #381).
const double _numberBoxWidth = 64;

/// Width a bare message box opens at — wider than a number box, because what
/// goes in it is words rather than digits.
const double _messageBoxWidth = 96;

/// Height of the one-line GUI controls — the two number boxes and the message
/// box (issue #381).
///
/// **Measured**, not chosen: it is exactly what an object box spends on its own
/// single line, so a row of mixed nodes sits on one baseline instead of stepping
/// — and so the readout inside a number box is guaranteed the height its font
/// actually needs, whatever font the app resolves at runtime.
double _guiLineBoxHeight() =>
    PatchObjectBoxMetrics.sizeFor(text: '0', inputs: 1, outputs: 1).height;
