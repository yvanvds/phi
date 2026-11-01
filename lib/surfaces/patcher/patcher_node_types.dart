import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_object_box_metrics.dart';
import '../../domain/patcher/item_list_args.dart';
import '../../domain/patcher/multislider_args.dart';
import '../../domain/patcher/patch_object_types.dart';
import '../../domain/patcher/patch_port_kind.dart';
import '../../engine/state/gui_value_read.dart';
import '../../engine/state/node_type_registry.dart';
import 'nodes/button_node_body.dart';
import 'nodes/dial_node_body.dart';
import 'nodes/incdec_node_body.dart';
import 'nodes/item_list_node_body.dart';
import 'nodes/label_switch_node_body.dart';
import 'nodes/list_node_body.dart';
import 'nodes/message_node_body.dart';
import 'nodes/multislider_node_body.dart';
import 'nodes/number_node_body.dart';
import 'nodes/range_slider_node_body.dart';
import 'nodes/slider_node_body.dart';
import 'nodes/textedit_node_body.dart';
import 'nodes/toggle_node_body.dart';
import 'nodes/xy_slider_node_body.dart';

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
      type: PatchObjectTypes.dSine,
      defaultArgs: '440',
      inputs: [PortSpec(kind: PatchPortKind.control, label: 'freq')],
      outputs: [PortSpec(kind: PatchPortKind.audio)],
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gSlider,
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
      type: PatchObjectTypes.dDac,
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
      type: PatchObjectTypes.gToggle,
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
      type: PatchObjectTypes.gButton,
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
      type: PatchObjectTypes.gFloat,
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
      type: PatchObjectTypes.gInt,
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
      type: PatchObjectTypes.gMessage,
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

  // ─── libYSE 3.0 single-value controls (issue #470) ─────────────────────
  // The pattern every later control follows (#471–#473): a `PatchObjectTypes`
  // id (with its drift-guard line), a visual-only `Patch…` widget under
  // `lib/design/widgets/patcher/`, a body under `nodes/` that writes through
  // the controller and follows the engine with a `GuiValueLink`, and one
  // block here. `defaultArgs` is the object's empty default — each of these
  // registers its parameters, so an empty string parses safely — and a body
  // that shows engine state sets `readsGuiValue` (all six do: `.l`'s stored
  // list is live state, unlike a `.m`'s arguments). One value each, so the
  // whole-state read (`GuiValueRead.whole`, the default) is the right one.

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gDial,
      // Square: the knob is the largest circle the node holds.
      defaultSize: const Size(_dialSize, _dialSize),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          DialNodeBody(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gIncdec,
      // Wide enough for its three inlets (value · nudge · step), and a
      // control's height so each half is a target of its own.
      defaultSize: Size(PatchCanvasConstants.minWidthForPorts(3), square),
      defaultArgs: '',
      inputs: const [
        PortSpec(kind: PatchPortKind.control, label: 'value'),
        PortSpec(kind: PatchPortKind.control, label: 'nudge'),
        PortSpec(kind: PatchPortKind.control, label: 'step'),
      ],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          IncdecNodeBody(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gLed,
      defaultSize: Size(_labelledControlWidth, lineHeight),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [
        PortSpec(kind: PatchPortKind.control, label: 'state'),
        PortSpec(kind: PatchPortKind.control, label: 'label'),
      ],
      buildBody: (ctx, node, controller) =>
          LabelSwitchNodeBody.led(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gTextbutton,
      defaultSize: Size(_labelledControlWidth, lineHeight),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [
        PortSpec(kind: PatchPortKind.control, label: 'state'),
        PortSpec(kind: PatchPortKind.control, label: 'label'),
      ],
      buildBody: (ctx, node, controller) =>
          LabelSwitchNodeBody.textButton(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gTextedit,
      defaultSize: Size(_textFieldWidth, lineHeight),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          TexteditNodeBody(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gList,
      defaultSize: Size(_messageBoxWidth, lineHeight),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [PortSpec(kind: PatchPortKind.control)],
      buildBody: (ctx, node, controller) =>
          ListNodeBody(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  // ─── libYSE 3.0 selection controls (issue #471) ────────────────────────
  // One engine object (`gItemListBase`) drawn three ways, so one body
  // (`ItemListNodeBody`) and one port shape: a hot inlet, and the item number,
  // its name and the whole selection out. Each control's box follows its
  // `items` argument (`sizeForArgs`), so a retype re-measures it. The GUI value
  // is the index, or with `multi` one flag per item — at most 256 short cells,
  // so the whole-state read is still the right one.

  const itemListInputs = [PortSpec(kind: PatchPortKind.control)];
  const itemListOutputs = [
    PortSpec(kind: PatchPortKind.control, label: 'index'),
    PortSpec(kind: PatchPortKind.control, label: 'item'),
    PortSpec(kind: PatchPortKind.control, label: 'state'),
  ];

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gUmenu,
      sizeForArgs: (args) => Size(
        _itemLabelWidth(ItemListArgs.parse(args)) + _menuChevronWidth,
        lineHeight,
      ),
      defaultArgs: '',
      inputs: itemListInputs,
      outputs: itemListOutputs,
      buildBody: (ctx, node, controller) =>
          ItemListNodeBody.menu(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gRadiogroup,
      sizeForArgs: (args) {
        final items = ItemListArgs.parse(args);
        // A row per item, each a one-line control's height, and room for the
        // mark beside the longest name.
        return Size(
          _itemLabelWidth(items) + lineHeight,
          items.count * lineHeight,
        );
      },
      defaultArgs: '',
      inputs: itemListInputs,
      outputs: itemListOutputs,
      buildBody: (ctx, node, controller) =>
          ItemListNodeBody.radioGroup(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gTab,
      sizeForArgs: (args) {
        final items = ItemListArgs.parse(args);
        // Equal tabs, each as wide as the longest name needs.
        return Size(items.count * _itemLabelWidth(items), lineHeight);
      },
      defaultArgs: '',
      inputs: itemListInputs,
      outputs: itemListOutputs,
      buildBody: (ctx, node, controller) =>
          ItemListNodeBody.tabs(node: node, controller: controller),
      readsGuiValue: true,
    ),
  );

  // ─── libYSE 3.0 multi-value sliders (issue #472) ───────────────────────
  // Controls whose GUI value is several cells — two ends, an x and a y, a
  // bank — in the object's own units inside its bound parameters. They are
  // polled per cell (`GuiValueRead.cells`), the protocol's form for multi-cell
  // state, and each body answers from the controller's cache of that read.
  // Upright like the `.slider`: a higher value is further up.

  const twoEndInputs = [
    PortSpec(kind: PatchPortKind.control),
    PortSpec(kind: PatchPortKind.control),
  ];

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gRslider,
      // A fader's throw tall, and as wide as its three outlets need.
      defaultSize: Size(PatchCanvasConstants.minWidthForPorts(3), 140),
      defaultArgs: '',
      inputs: twoEndInputs,
      outputs: const [
        PortSpec(kind: PatchPortKind.control, label: 'low'),
        PortSpec(kind: PatchPortKind.control, label: 'high'),
        PortSpec(kind: PatchPortKind.control, label: 'range'),
      ],
      buildBody: (ctx, node, controller) =>
          RangeSliderNodeBody(node: node, controller: controller),
      readsGuiValue: true,
      guiValueRead: GuiValueRead.cells,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gXyslider,
      // Square: one surface for two equal axes.
      defaultSize: const Size(_xyPadSize, _xyPadSize),
      defaultArgs: '',
      inputs: twoEndInputs,
      outputs: const [
        PortSpec(kind: PatchPortKind.control, label: 'x'),
        PortSpec(kind: PatchPortKind.control, label: 'y'),
        PortSpec(kind: PatchPortKind.control, label: 'position'),
      ],
      buildBody: (ctx, node, controller) =>
          XySliderNodeBody(node: node, controller: controller),
      readsGuiValue: true,
      guiValueRead: GuiValueRead.cells,
    ),
  );

  registry.register(
    NodeDescriptor(
      type: PatchObjectTypes.gMultislider,
      // As wide as its `size` argument asks — a bar's width each, inside a
      // floor for the ports and a ceiling a 1024-cell bank cannot push past.
      sizeForArgs: (args) => Size(
        (MultisliderArgs.parse(args).size * _bankBarWidth).clamp(
          PatchCanvasConstants.minWidthForPorts(2),
          _bankMaxWidth,
        ),
        _bankHeight,
      ),
      defaultArgs: '',
      inputs: const [PortSpec(kind: PatchPortKind.control)],
      outputs: const [
        PortSpec(kind: PatchPortKind.control, label: 'bank'),
        PortSpec(kind: PatchPortKind.control, label: 'cell'),
      ],
      buildBody: (ctx, node, controller) =>
          MultisliderNodeBody(node: node, controller: controller),
      readsGuiValue: true,
      guiValueRead: GuiValueRead.cells,
    ),
  );
}

/// Side of a `.xyslider` pad (issue #472).
const double _xyPadSize = 120;

/// Width of one `.multislider` bar at creation (issue #472).
const double _bankBarWidth = 14;

/// The widest a `.multislider` opens at, however many cells it is built with.
const double _bankMaxWidth = 384;

/// Height of a `.multislider` — a fader's throw.
const double _bankHeight = 110;

/// The width the longest of [items]' names needs on one line — measured the
/// way an object box measures its line, padding and border included, so a name
/// fits wherever the box allowed it to (issue #471).
double _itemLabelWidth(ItemListArgs items) {
  var widest = 0.0;
  for (final label in items.labels) {
    widest = math.max(
      widest,
      PatchObjectBoxMetrics.sizeFor(text: label, inputs: 0, outputs: 0).width,
    );
  }
  return widest;
}

/// Room a `.umenu` keeps right of its name for the drop-down chevron.
const double _menuChevronWidth = 24;

/// Width a bare number box opens at — room for a few digits and their sign
/// before the cut corner, and no more: a readout that says `0.5` has no use for
/// the 110px the old `NUMBER · F` frame spent (issue #381).
const double _numberBoxWidth = 64;

/// Width a bare message box opens at — wider than a number box, because what
/// goes in it is words rather than digits.
const double _messageBoxWidth = 96;

/// Side of a `.dial` — room for the knob and, in the gap at its foot, a
/// readout of a few digits (issue #470).
const double _dialSize = 56;

/// Width a `.led` / `.textbutton` opens at — a short label's worth beside the
/// lamp, or across the button.
const double _labelledControlWidth = 96;

/// Width a `.textedit` opens at — a few words.
const double _textFieldWidth = 128;

/// Height of the one-line GUI controls — the two number boxes and the message
/// box (issue #381), and since #470 the `.led`, `.textbutton`, `.textedit` and
/// `.l`.
///
/// **Measured**, not chosen: it is exactly what an object box spends on its own
/// single line, so a row of mixed nodes sits on one baseline instead of stepping
/// — and so the readout inside a number box is guaranteed the height its font
/// actually needs, whatever font the app resolves at runtime.
double _guiLineBoxHeight() =>
    PatchObjectBoxMetrics.sizeFor(text: '0', inputs: 1, outputs: 1).height;
