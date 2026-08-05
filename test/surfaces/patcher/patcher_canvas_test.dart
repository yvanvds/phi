import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';
import 'package:phi/domain/patcher/patch_args.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_ghost_cable.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Drives the reworked patcher canvas (issue #222): body drag, typed cables,
/// marquee + shift-click, cable/node delete, duplicate — each with undo/redo,
/// exercised through real pointer + keyboard gestures.
///
/// Node dragging is driven from the canvas's raw pointer pipeline (issue #352),
/// so the drag cases below assert *exact* positions — on screen as well as in
/// the model — rather than "it moved somewhat": nothing may be swallowed by a
/// recogniser's slop, and nothing may lag behind the pointer at any zoom.
void main() {
  NodeDescriptor desc(String type, {Widget? body}) => NodeDescriptor(
    type: type,
    defaultSize: const Size(80, 60),
    defaultArgs: '',
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => body ?? const SizedBox.shrink(),
  );

  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    NodeTypeRegistry.instance.clear();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() {
    controller.dispose();
    NodeTypeRegistry.instance.clear();
  });

  /// The mode the canvas is currently pumped in — held outside the widget, the
  /// way the real surface holds it, so `Ctrl+E` and the toggle can actually
  /// change it mid-test (issue #378).
  late PatchCanvasMode mode;

  /// Rebuilds the pumped canvas with a new [mode] — the host's half of the
  /// toggle, i.e. what the placement bar's button does.
  late StateSetter setHostState;

  Future<void> pumpCanvas(
    WidgetTester tester, {
    List<PatchObjectDescriptor> objectTypes = const [],
    bool snapToGrid = false,
    PatchCanvasMode initialMode = PatchCanvasMode.edit,
    bool toggleable = true,
    void Function(
      PatchObjectDescriptor desc,
      Offset canvasPosition, {
      String? args,
    })?
    onCreateObject,
    void Function(PatchNode node)? onNodeDoubleTap,
    void Function(PatchNode node)? onNodeTap,
    void Function(PatchNode node, Offset globalPosition)? onNodeContextMenu,
  }) async {
    mode = initialMode;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return PatcherCanvas(
                controller: controller,
                objectTypes: objectTypes,
                snapToGrid: snapToGrid,
                mode: mode,
                onToggleMode: toggleable
                    ? () => setState(() => mode = mode.flipped)
                    : null,
                onCreateObject: onCreateObject,
                onNodeTap: onNodeTap,
                onNodeDoubleTap: onNodeDoubleTap,
                onNodeContextMenu: onNodeContextMenu,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Flip the pumped canvas into [next] from outside, the way the placement
  /// bar's toggle does (issue #378).
  Future<void> setMode(WidgetTester tester, PatchCanvasMode next) async {
    setHostState(() => mode = next);
    await tester.pump();
  }

  /// A right-click at [at] — the raw secondary-button press the canvas reads
  /// out of its own pointer stream.
  Future<void> rightClickAt(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await g.up();
    await tester.pump();
  }

  /// A parked mouse pointer, so hover-driven affordances can be driven the way
  /// a real one drives them (issue #359).
  Future<TestGesture> mouse(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(() => g.removePointer());
    await tester.pump();
    return g;
  }

  /// The cursor the tracker actually resolved. Read from the tracker rather
  /// than from a widget lookup: the canvas answers for the whole viewport out
  /// of one region, in scene space, so only the tracker knows what landed under
  /// the pointer. Device `1` is what `flutter_test` gives a mouse.
  MouseCursor? activeCursor() =>
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

  /// A point that is **on** the cable between [a] and [b] and inside the grab
  /// band around one of its ends — past the port's own press radius, short of
  /// [PatchCanvasConstants.cableGrabRadius]. Searched rather than guessed so
  /// the test keeps meaning what it says if either radius is retuned.
  Offset grabPoint(Offset a, Offset b, {required bool atSource}) {
    final end = atSource ? a : b;
    for (var i = 1; i < 60; i++) {
      final t = atSource ? i / 60 : 1 - i / 60;
      final p = PatchCableGeometry.pointAt(a, b, t);
      final d = (p - end).distance;
      if (d > PatchCanvasConstants.portPressRadius + 2 &&
          d < PatchCanvasConstants.cableGrabRadius - 2) {
        return p;
      }
    }
    fail('no point on the cable falls inside the grab band');
  }

  /// Where the node's chrome actually sits on screen — the model position is
  /// only half the story, since the canvas lays each node out from its own
  /// build. Found by the *view*, which is the node whichever chrome it wears:
  /// a frame for a GUI body, an object box for a plain engine object
  /// (issue #379).
  Offset frameTopLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PatcherNodeView));

  Offset canvasTL(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PatcherCanvas));

  Offset portGlobal(
    WidgetTester tester,
    PatchNode node,
    PatchPortSide side,
    int i,
  ) {
    final scene = portPositionsFor(
      node,
    )[PatchPortId(nodeId: node.id, side: side, index: i)]!;
    return canvasTL(tester) + scene;
  }

  Offset nodeCenter(WidgetTester tester, PatchNode node) =>
      canvasTL(tester) +
      Offset(
        node.position.dx + node.size.width / 2,
        node.position.dy + node.size.height / 2,
      );

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  PatchPortId out(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.output, index: i);
  PatchPortId inp(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.input, index: i);

  testWidgets('body drag moves the node and undoes/redoes', (tester) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);
    const start = Offset(120, 120);
    final drawnAtStart = frameTopLeft(tester);

    // A stepped drag. Every pixel of it lands on the node: the first step's
    // slop distance is carried into the move instead of being discarded.
    final g = await tester.startGesture(nodeCenter(tester, sine));
    await tester.pump();
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(30, 25));
    await tester.pump();

    // Mid-gesture the node is already drawn under the pointer, not lagging it.
    expect(frameTopLeft(tester), drawnAtStart + const Offset(60, 25));

    await g.up();
    await tester.pump();

    final moved = start + const Offset(60, 25);
    expect(sine.position, moved);

    // The drag focused the canvas, so Ctrl+Z reaches its undo scope; undo/redo
    // restore and re-apply the move exactly — on screen too.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(sine.position, start);
    expect(frameTopLeft(tester), drawnAtStart);

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(sine.position, moved);
    expect(frameTopLeft(tester), drawnAtStart + const Offset(60, 25));
  });

  testWidgets('a drag shorter than the gesture-arena touch slop still moves '
      'the node, one-to-one', (tester) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);
    final drawnAtStart = frameTopLeft(tester);

    // 6px — past the canvas's own 4px click slop but well under `kTouchSlop`
    // (~18px), which a pan recogniser would have needed before accepting.
    final g = await tester.startGesture(nodeCenter(tester, sine));
    await tester.pump();
    await g.moveBy(const Offset(6, 6));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(sine.position, const Offset(126, 126));
    expect(frameTopLeft(tester), drawnAtStart + const Offset(6, 6));
  });

  testWidgets('the node stays under the pointer while zoomed in', (
    tester,
  ) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);
    controller.transform.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    final drawnAtStart = frameTopLeft(tester);

    // At 2× the node's header centre — scene (160, 131) — is twice as far from
    // the canvas origin, and a 40px pointer move is a 20px move in the scene.
    final g = await tester.startGesture(
      canvasTL(tester) + const Offset(320, 262),
    );
    await tester.pump();
    await g.moveBy(const Offset(40, 20));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(sine.position, const Offset(140, 130));
    // On screen the node followed the pointer exactly, not half of it.
    expect(frameTopLeft(tester), drawnAtStart + const Offset(40, 20));
  });

  testWidgets('click-to-select then drag moves the node and never reports a '
      'double-click', (tester) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    PatchNode? doubleClicked;
    await pumpCanvas(tester, onNodeDoubleTap: (n) => doubleClicked = n);

    await tester.tapAt(nodeCenter(tester, sine));
    await tester.pump();
    expect(controller.graph.selectedNodes, {sine.id});

    // The very next press starts a drag — a press that moves is not a click,
    // so it can never be the second half of a double-click.
    final g = await tester.startGesture(nodeCenter(tester, sine));
    await tester.pump();
    await g.moveBy(const Offset(24, 18));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(doubleClicked, isNull);
    expect(sine.position, const Offset(144, 138));
  });

  testWidgets('two movement-free clicks on a node report a double-click', (
    tester,
  ) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    PatchNode? doubleClicked;
    await pumpCanvas(tester, onNodeDoubleTap: (n) => doubleClicked = n);

    final at = nodeCenter(tester, sine);
    await tester.tapAt(at);
    await tester.pump();
    await tester.tapAt(at);
    await tester.pump();

    expect(doubleClicked?.id, sine.id);
  });

  testWidgets('a press beside an outlet but inside the node drags the node, '
      'not a cable', (tester) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);

    // Scene (198, 145): inside the node, 13px from its outlet centre at
    // (200, 158) — inside the generous drop radius, outside the press radius.
    final g = await tester.startGesture(
      canvasTL(tester) + const Offset(198, 145),
    );
    await tester.pump();
    await g.moveBy(const Offset(25, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(sine.position, const Offset(145, 120));
    expect(controller.graph.cables, isEmpty);
  });

  // ─── editable bodies keep focus and keys (issue #353) ───────────────────

  /// A real `.f` number node, registered as well as returned: the canvas
  /// renders the body out of the registry, not out of what was passed in.
  NodeDescriptor numberDesc() {
    final d = NodeDescriptor(
      type: Obj.gFloat,
      defaultSize: const Size(110, 70),
      defaultArgs: '',
      inputs: const [],
      outputs: const [],
      buildBody: (ctx, node, controller) =>
          NumberNodeBody(node: node, controller: controller),
    );
    NodeTypeRegistry.instance.register(d);
    return d;
  }

  FocusNode fieldFocus(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!;

  testWidgets('a click on a number readout focuses its field, and a press '
      'elsewhere inside the box does not take it back', (tester) async {
    final number = controller.addNode(
      desc: numberDesc(),
      position: const Offset(120, 120),
    );
    // Run mode: where a body answers a press at all (issue #378). The #353
    // rules — the field takes the caret, the canvas never takes it back — are
    // about that mode, since it is the only one in which the field is live.
    await pumpCanvas(tester, initialMode: PatchCanvasMode.run);

    await tester.tapAt(tester.getCenter(find.byType(TextField)));
    await tester.pump();
    await tester.pump();

    expect(fieldFocus(tester).hasPrimaryFocus, isTrue);
    // The press belonged to the body: no selection, no move.
    expect(controller.graph.selectedNodes, isEmpty);
    expect(number.position, const Offset(120, 120));

    // Scene (126, 146): inside the node's body rect but in the padding beside
    // the readout, so no widget claims it. The canvas must still keep its hands
    // off the caret.
    await tester.tapAt(canvasTL(tester) + const Offset(126, 146));
    await tester.pump();
    await tester.pump();

    expect(fieldFocus(tester).hasPrimaryFocus, isTrue);
  });

  testWidgets('Backspace while a number field is focused edits the text, '
      'never the canvas selection', (tester) async {
    controller.addNode(desc: numberDesc(), position: const Offset(120, 120));
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(320, 120),
    );
    // Edit mode first: select the sine, so there is something Delete could
    // wrongly take away once the field holds the keyboard.
    await pumpCanvas(tester);
    await tester.tapAt(nodeCenter(tester, sine));
    await tester.pump();
    expect(controller.graph.selectedNodes, {sine.id});

    // Now run mode, where the field is live — and edit it.
    await setMode(tester, PatchCanvasMode.run);
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
    // The graph survived untouched: the key belonged to the field.
    expect(controller.graph.nodes, hasLength(2));
    expect(controller.graph.selectedNodes, {sine.id});

    // And once the canvas has focus again, back in edit mode, Delete still
    // removes the selection.
    await setMode(tester, PatchCanvasMode.edit);
    await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
    await tester.pump();
    await tester.tapAt(nodeCenter(tester, sine));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(controller.graph.nodes, hasLength(1));
  });

  testWidgets('in edit mode a press on the number readout selects and drags '
      'its node instead of taking the caret', (tester) async {
    final number = controller.addNode(
      desc: numberDesc(),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);

    // Straight onto the readout — which in edit mode is inert chrome like any
    // other pixel of the box (issue #378).
    final readout = tester.getCenter(find.byType(TextField));
    final g = await tester.startGesture(readout);
    await tester.pump();
    await g.moveBy(const Offset(30, 20));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(number.position, const Offset(150, 140));
    expect(fieldFocus(tester).hasPrimaryFocus, isFalse);

    await tester.tapAt(nodeCenter(tester, number));
    await tester.pump();
    expect(controller.graph.selectedNodes, {number.id});
    expect(fieldFocus(tester).hasPrimaryFocus, isFalse);
  });

  testWidgets('a compatible cable drop connects; undo disconnects', (
    tester,
  ) async {
    final slider = controller.addNode(
      desc: desc(Obj.gSlider),
      position: const Offset(100, 120),
    );
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(300, 120),
    );
    await pumpCanvas(tester);

    // Press the slider's outlet (just past the node's right edge), drag to the
    // sine's inlet, release.
    final g = await tester.startGesture(
      portGlobal(tester, slider, PatchPortSide.output, 0),
    );
    await tester.pump();
    await g.moveTo(portGlobal(tester, sine, PatchPortSide.input, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(controller.graph.cables, hasLength(1));
    expect(gateway.cables, hasLength(1));

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(controller.graph.cables, isEmpty);
  });

  testWidgets('an incompatible cable drop is rejected visibly', (tester) async {
    final slider = controller.addNode(
      desc: desc(Obj.gSlider),
      position: const Offset(100, 120),
    );
    final dac = controller.addNode(
      desc: desc(Obj.dDac),
      position: const Offset(300, 120),
    );
    await pumpCanvas(tester);

    final g = await tester.startGesture(
      portGlobal(tester, slider, PatchPortSide.output, 0),
    );
    await tester.pump();
    await g.moveTo(portGlobal(tester, dac, PatchPortSide.input, 0));
    await tester.pump();
    await g.up();
    await tester.pump();

    // float → DSP inlet is refused: no cable, and the reject banner shows.
    expect(controller.graph.cables, isEmpty);
    expect(find.byKey(PatcherCanvas.rejectKey), findsOneWidget);
  });

  testWidgets('clicking a cable selects it; Delete removes it; undo restores', (
    tester,
  ) async {
    final slider = controller.addNode(
      desc: desc(Obj.gSlider),
      position: const Offset(100, 120),
    );
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(300, 120),
    );
    controller.connectViaGesture(out(slider, 0), inp(sine, 0));
    await pumpCanvas(tester);
    expect(controller.graph.cables, hasLength(1));

    // Tap the midpoint of the cable's cubic.
    final a = portPositionsFor(slider)[out(slider, 0)]!;
    final b = portPositionsFor(sine)[inp(sine, 0)]!;
    final mid = canvasTL(tester) + PatchCableGeometry.pointAt(a, b, 0.5);
    await tester.tapAt(mid);
    await tester.pump();
    expect(controller.graph.selectedCable, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(controller.graph.cables, isEmpty);

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(controller.graph.cables, hasLength(1));
  });

  testWidgets('marquee selects covered nodes; shift-click toggles one off', (
    tester,
  ) async {
    final a = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    final b = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 240),
    );
    await pumpCanvas(tester);

    final tl = canvasTL(tester);
    final g = await tester.startGesture(tl + const Offset(60, 80));
    await tester.pump();
    await g.moveTo(tl + const Offset(260, 320));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(controller.graph.selectedNodes, {a.id, b.id});

    // Shift-click node A to drop it from the selection.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(nodeCenter(tester, a));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.graph.selectedNodes, {b.id});
  });

  testWidgets('Delete on a multi-node selection removes nodes and their '
      'cables; undo restores', (tester) async {
    final slider = controller.addNode(
      desc: desc(Obj.gSlider),
      position: const Offset(120, 120),
    );
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 240),
    );
    controller.connectViaGesture(out(slider, 0), inp(sine, 0));
    await pumpCanvas(tester);

    // Marquee both nodes.
    final tl = canvasTL(tester);
    final g = await tester.startGesture(tl + const Offset(60, 80));
    await tester.pump();
    await g.moveTo(tl + const Offset(280, 340));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(controller.graph.selectedNodes, {slider.id, sine.id});

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(controller.graph.nodes, isEmpty);
    expect(controller.graph.cables, isEmpty);

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(controller.graph.nodes, hasLength(2));
    expect(controller.graph.cables, hasLength(1));
  });

  testWidgets('Ctrl+D duplicates the selection; undo removes the copies', (
    tester,
  ) async {
    final sine = controller.addNode(
      desc: desc(Obj.dSine),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);

    // Click to select, then duplicate.
    await tester.tapAt(nodeCenter(tester, sine));
    await tester.pump();
    expect(controller.graph.selectedNodes, {sine.id});

    await ctrl(tester, LogicalKeyboardKey.keyD);
    expect(controller.graph.nodes, hasLength(2));

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(controller.graph.nodes, hasLength(1));

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(controller.graph.nodes, hasLength(2));
  });

  // ─── keyboard nudge + grid snap on drop (issue #368) ─────────────────────
  //
  // Both ride the machinery a body drag already uses, so what these cases are
  // really about is the *boundaries*: where a burst of repeats begins and ends
  // (one undo step, not one per repeat), and where a drop is quantised.

  group('keyboard nudge', () {
    /// A whole arrow keypress — down, [repeats] auto-repeats while it is held,
    /// then up. The release is what closes the burst and journals it.
    Future<void> arrow(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      int repeats = 0,
      bool shift = false,
    }) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      for (var i = 0; i < repeats; i++) {
        await tester.sendKeyRepeatEvent(key);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    /// Select [node] by clicking it — which is also how the canvas comes to
    /// hold the keyboard, so every nudge below starts the way a real one does.
    Future<void> selectByClick(WidgetTester tester, PatchNode node) async {
      await tester.tapAt(nodeCenter(tester, node));
      await tester.pump();
      expect(controller.graph.selectedNodes, {node.id});
    }

    testWidgets('an arrow moves the selection one grid cell, on screen too', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      final drawnAtStart = frameTopLeft(tester);
      await selectByClick(tester, sine);

      await arrow(tester, LogicalKeyboardKey.arrowRight);
      expect(sine.position, const Offset(136, 120));
      expect(frameTopLeft(tester), drawnAtStart + const Offset(16, 0));

      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(sine.position, const Offset(136, 136));

      // Two presses, two steps: a press is a burst of its own.
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(136, 120));
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(120, 120));
      expect(frameTopLeft(tester), drawnAtStart);
    });

    testWidgets('a held arrow moves on every repeat but undoes as one step', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await selectByClick(tester, sine);

      await arrow(tester, LogicalKeyboardKey.arrowRight, repeats: 3);

      // Four events — the press and three repeats — each moved a cell.
      expect(sine.position, const Offset(184, 120));

      // …and the whole burst comes back on one Ctrl+Z, which is the point:
      // one command per repeat would make undo useless on a nudged canvas.
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(120, 120));
      expect(controller.undoScope.canUndo, isFalse);

      await ctrl(tester, LogicalKeyboardKey.keyY);
      expect(sine.position, const Offset(184, 120));
    });

    testWidgets('Shift+arrow moves a major cell', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await selectByClick(tester, sine);

      await arrow(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(sine.position, const Offset(120, 184));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(120, 120));
    });

    testWidgets('the whole selection nudges together', (tester) async {
      final a = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      final b = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      await pumpCanvas(tester);
      controller.selectNodes({a.id, b.id});
      // Focus the canvas without disturbing the selection a marquee-style
      // multi-select left behind.
      await tester.tapAt(nodeCenter(tester, a));
      await tester.pump();
      controller.selectNodes({a.id, b.id});
      await tester.pump();

      await arrow(tester, LogicalKeyboardKey.arrowLeft);
      expect(a.position, const Offset(104, 120));
      expect(b.position, const Offset(304, 120));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(a.position, const Offset(120, 120));
      expect(b.position, const Offset(320, 120));
    });

    testWidgets('an arrow while a number field is focused edits the field, '
        'never the canvas selection', (tester) async {
      controller.addNode(desc: numberDesc(), position: const Offset(120, 120));
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      await pumpCanvas(tester);

      await tester.tapAt(nodeCenter(tester, sine));
      await tester.pump();
      expect(controller.graph.selectedNodes, {sine.id});

      // The caret goes into the `.f` box; the canvas no longer holds the
      // keyboard, so its arrow shortcut must stay out of the way (issue #353).
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      expect(fieldFocus(tester).hasPrimaryFocus, isTrue);

      await arrow(tester, LogicalKeyboardKey.arrowLeft, repeats: 2);

      expect(sine.position, const Offset(320, 120));
      expect(controller.undoScope.canUndo, isFalse);
      expect(controller.graph.selectedNodes, {sine.id});
    });

    testWidgets('an arrow with nothing selected moves nothing', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);

      // Click empty canvas: focus without a selection.
      await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
      await tester.pump();
      expect(controller.graph.selectedNodes, isEmpty);

      await arrow(tester, LogicalKeyboardKey.arrowRight);
      expect(sine.position, const Offset(120, 120));
      expect(controller.undoScope.canUndo, isFalse);
    });

    testWidgets('a press mid-burst commits the pending nudge', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await selectByClick(tester, sine);

      // Arrow down and *held* — no release, so the burst is still open.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(sine.position, const Offset(136, 120));
      expect(controller.undoScope.canUndo, isFalse);

      // A press starts a new gesture, which would otherwise overwrite the
      // origins the burst is measured from and lose the move for good.
      await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(sine.position, const Offset(136, 120));
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(120, 120));
    });
  });

  group('grid snap on drop', () {
    testWidgets('off by default: a drop lands where the pointer left it', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(40, 60),
      );
      await pumpCanvas(tester);

      final g = await tester.startGesture(nodeCenter(tester, sine));
      await tester.pump();
      await g.moveBy(const Offset(7, 3));
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(sine.position, const Offset(47, 63));
    });

    testWidgets('on: a drop quantises to the grid, on screen too, and undo '
        'restores the off-grid origin', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(40, 60),
      );
      await pumpCanvas(tester, snapToGrid: true);
      final drawnAtStart = frameTopLeft(tester);

      final g = await tester.startGesture(nodeCenter(tester, sine));
      await tester.pump();
      await g.moveBy(const Offset(7, 3));
      await tester.pump();
      // Mid-drag the node is still glued to the pointer: only the *drop* is
      // disciplined, so dragging never feels like it is fighting the grid.
      expect(frameTopLeft(tester), drawnAtStart + const Offset(7, 3));

      await g.up();
      await tester.pump();

      expect(sine.position, const Offset(48, 64));
      expect(frameTopLeft(tester), drawnAtStart + const Offset(8, 4));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(40, 60));
      expect(frameTopLeft(tester), drawnAtStart);
    });

    testWidgets('on: a nudge lands on the grid as well', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(44, 60),
      );
      await pumpCanvas(tester, snapToGrid: true);

      await tester.tapAt(nodeCenter(tester, sine));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      // Live, the nudge is a plain grid step off wherever the node was.
      expect(sine.position, const Offset(60, 60));

      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      // The release is the drop, so it snaps — and the whole thing is one step.
      expect(sine.position, const Offset(64, 64));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(44, 60));
    });
  });

  // ─── right-click opens the node context menu (issue #356) ────────────────
  //
  // The secondary button is read from the canvas's own raw pointer pipeline, so
  // these cases also prove it does not disturb the primary-button gestures that
  // pipeline already owns.

  group('right-click', () {
    testWidgets('reports the node under the pointer and selects it', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      PatchNode? menuFor;
      Offset? menuAt;
      await pumpCanvas(
        tester,
        onNodeContextMenu: (n, at) {
          menuFor = n;
          menuAt = at;
        },
      );

      final at = nodeCenter(tester, sine);
      await rightClickAt(tester, at);

      expect(menuFor?.id, sine.id);
      expect(menuAt, at);
      // The verbs on the menu act on the selection, so the click has to have
      // made its node the selection first.
      expect(controller.graph.selectedNodes, {sine.id});
    });

    testWidgets('inside a multi-selection keeps the whole selection', (
      tester,
    ) async {
      final a = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      final b = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 240),
      );
      await pumpCanvas(tester, onNodeContextMenu: (_, _) {});
      controller.selectNodes({a.id, b.id});
      await tester.pump();

      await rightClickAt(tester, nodeCenter(tester, b));

      // `delete` from here removes both — right-clicking one member of a group
      // must not silently shrink the group first.
      expect(controller.graph.selectedNodes, {a.id, b.id});
    });

    testWidgets('outside the selection re-points it at the clicked node', (
      tester,
    ) async {
      final a = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      final b = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 240),
      );
      await pumpCanvas(tester, onNodeContextMenu: (_, _) {});
      controller.selectNodes({a.id});
      await tester.pump();

      await rightClickAt(tester, nodeCenter(tester, b));

      expect(controller.graph.selectedNodes, {b.id});
    });

    testWidgets('on empty canvas opens nothing and leaves the selection', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      var opened = 0;
      await pumpCanvas(tester, onNodeContextMenu: (_, _) => opened++);
      controller.selectNodes({sine.id});
      await tester.pump();

      await rightClickAt(tester, canvasTL(tester) + const Offset(600, 500));

      expect(opened, 0);
      expect(controller.graph.selectedNodes, {sine.id});
    });

    testWidgets('never counts towards a double-click or moves the node', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      PatchNode? doubleClicked;
      await pumpCanvas(
        tester,
        onNodeDoubleTap: (n) => doubleClicked = n,
        onNodeContextMenu: (_, _) {},
      );

      final at = nodeCenter(tester, sine);
      await tester.tapAt(at);
      await tester.pump();
      await rightClickAt(tester, at);
      await tester.tapAt(at);
      await tester.pump();

      // A right-click is its own gesture: it neither completes the pending
      // left-click pairing nor drags the node it landed on.
      expect(doubleClicked, isNull);
      expect(sine.position, const Offset(120, 120));
    });
  });

  // ─── a params change reshapes the drawn node (issue #356) ────────────────

  testWidgets('a params change that adds an outlet draws the new port', (
    tester,
  ) async {
    // Outlets follow the argument count, the way a `.select`-style object's do.
    gateway.topologyResolver = (type, args) {
      if (type != '.fan') return null;
      final outlets = splitPatchArgs(args).length;
      return PatcherNodeSnapshot(
        inputs: 0,
        outputs: outlets,
        inputKinds: const [],
        outputKinds: [for (var i = 0; i < outlets; i++) PatchPortKind.control],
      );
    };
    final fan = controller.addNode(
      desc: NodeDescriptor(
        type: '.fan',
        defaultSize: const Size(120, 64),
        defaultArgs: '1 2',
        inputs: const [],
        outputs: const [],
        buildBody: (ctx, node, controller) => const SizedBox.shrink(),
      ),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);
    expect(find.byType(PatchPortDot), findsNWidgets(2));

    controller.applyParams(fan.id, '1 2 3');
    await tester.pump();

    // The canvas draws what the engine now has, not what it had when the node
    // was created.
    expect(fan.outputs, hasLength(3));
    expect(find.byType(PatchPortDot), findsNWidgets(3));
  });

  // ─── cancelled gestures leave nothing behind (issue #355) ────────────────
  //
  // A pointer can be torn away mid-gesture — the window loses capture, a dialog
  // opens over the press, a system drag claims the pointer — and then the
  // pointer-up the gesture was waiting for never arrives. Each case below drives
  // a real `PointerCancelEvent` into a gesture in flight and asserts that both
  // the visible artifact and the state behind it are gone, *and* that the canvas
  // still works straight afterwards.

  group('cancelled gestures', () {
    testWidgets('a cancelled marquee leaves no rectangle and no selection', (
      tester,
    ) async {
      final a = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);

      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(60, 80));
      await tester.pump();
      await g.moveTo(tl + const Offset(260, 320));
      await tester.pump();
      // The rubber band is up and covers the node.
      expect(find.byKey(PatcherCanvas.marqueeKey), findsOneWidget);

      await g.cancel();
      await tester.pump();

      // The grey rectangle is gone — it is not left painted over the scene —
      // and an abandoned marquee selects nothing.
      expect(find.byKey(PatcherCanvas.marqueeKey), findsNothing);
      expect(controller.graph.selectedNodes, isEmpty);

      // The canvas is immediately usable: a fresh marquee still selects.
      final again = await tester.startGesture(tl + const Offset(60, 80));
      await tester.pump();
      await again.moveTo(tl + const Offset(260, 320));
      await tester.pump();
      await again.up();
      await tester.pump();
      expect(controller.graph.selectedNodes, {a.id});
    });

    testWidgets('a cancelled re-route puts the cable back and journals '
        'nothing', (tester) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(300, 120),
      );
      controller.connect(out(slider, 0), inp(sine, 0));
      await pumpCanvas(tester);

      final a = portPositionsFor(slider)[out(slider, 0)]!;
      final b = portPositionsFor(sine)[inp(sine, 0)]!;
      final g = await tester.startGesture(
        canvasTL(tester) + grabPoint(a, b, atSource: false),
      );
      await tester.pump();
      await g.moveTo(canvasTL(tester) + const Offset(240, 320));
      await tester.pump();
      // The cable really is off — this is the state a torn-away pointer would
      // otherwise strand.
      expect(controller.graph.cables, isEmpty);
      expect(controller.reroutingCable, isNotNull);

      await g.cancel();
      await tester.pump();

      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
      expect(controller.reroutingCable, isNull);
      expect(controller.graph.dragSourcePort, isNull);
      // A gesture nobody finished is not an edit.
      expect(controller.undoScope.canUndo, isFalse);
    });

    testWidgets('a cancelled cable drag drops the ghost and frees the canvas', (
      tester,
    ) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(300, 120),
      );
      await pumpCanvas(tester);

      final g = await tester.startGesture(
        portGlobal(tester, slider, PatchPortSide.output, 0),
      );
      await tester.pump();
      await g.moveTo(canvasTL(tester) + const Offset(240, 150));
      await tester.pump();
      expect(controller.graph.dragSourcePort, isNotNull);
      expect(find.byType(PatcherGhostCable), findsOneWidget);

      await g.cancel();
      await tester.pump();

      // No stuck ghost glued to the cursor, no half-made cable.
      expect(controller.graph.dragSourcePort, isNull);
      expect(find.byType(PatcherGhostCable), findsNothing);
      expect(controller.graph.cables, isEmpty);

      // And the canvas is not inert: while a source port is stuck every press
      // is swallowed, so this drag would have done nothing at all.
      final drag = await tester.startGesture(nodeCenter(tester, sine));
      await tester.pump();
      await drag.moveBy(const Offset(30, 20));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(sine.position, const Offset(330, 140));
    });

    testWidgets('a cancelled node drag puts the node back and journals '
        'nothing', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      final drawnAtStart = frameTopLeft(tester);

      final g = await tester.startGesture(nodeCenter(tester, sine));
      await tester.pump();
      await g.moveBy(const Offset(60, 40));
      await tester.pump();
      expect(sine.position, const Offset(180, 160)); // the live preview

      await g.cancel();
      await tester.pump();

      // The gesture never happened: the node is back where the press found it,
      // on screen as well as in the model, and no half-move reached the stack.
      expect(sine.position, const Offset(120, 120));
      expect(frameTopLeft(tester), drawnAtStart);
      expect(controller.undoScope.canUndo, isFalse);

      // A real drag right after still commits — no drag origins leaked.
      final again = await tester.startGesture(nodeCenter(tester, sine));
      await tester.pump();
      await again.moveBy(const Offset(20, 10));
      await tester.pump();
      await again.up();
      await tester.pump();
      expect(sine.position, const Offset(140, 130));
      expect(controller.undoScope.canUndo, isTrue);
    });

    testWidgets('a cancelled press is never half of a double-click', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      PatchNode? doubleClicked;
      await pumpCanvas(tester, onNodeDoubleTap: (n) => doubleClicked = n);

      final at = nodeCenter(tester, sine);
      await tester.tapAt(at);
      await tester.pump();

      // The user starts a second press on the node and it is torn away.
      final g = await tester.startGesture(at);
      await tester.pump();
      await g.cancel();
      await tester.pump();

      // The next click opens a *new* pairing rather than completing the one the
      // cancelled gesture interrupted — otherwise the params dialog opens off a
      // gesture the user abandoned.
      await tester.tapAt(at);
      await tester.pump();
      expect(doubleClicked, isNull);

      // Two clean clicks still pair, so the reset did not break double-click.
      await tester.tapAt(at);
      await tester.pump();
      expect(doubleClicked?.id, sine.id);
    });

    testWidgets('a cancelled middle-drag pan does not swallow the next '
        'gesture', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);

      final tl = canvasTL(tester);
      final pan = await tester.startGesture(
        tl + const Offset(400, 400),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await tester.pump();
      await pan.moveBy(const Offset(-20, -10));
      await tester.pump();
      expect(controller.transform.value.getTranslation().x, -20);

      await pan.cancel();
      await tester.pump();

      // With `_panning` stuck the release below is read as the end of a pan and
      // the whole gesture is discarded — no marquee, no selection.
      final g = await tester.startGesture(tl + const Offset(40, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(240, 300));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(controller.graph.selectedNodes, {sine.id});
    });
  });

  // ─── inline object creation (issue #358) ─────────────────────────────────
  //
  // The Max speed path: double-click empty canvas → an object box appears there
  // → type a name (+ args) → Enter. These drive the *canvas* half — which
  // clicks pair into a box, where the box lands, and that a create round-trips
  // onto the undo stack without the hand leaving the keyboard. The box's own
  // keys, completion and refusals are covered in
  // `patch_inline_object_box_test.dart`.

  group('inline object creation', () {
    /// The catalogue the palette renders — the box completes against the same
    /// source, so the two gestures can never disagree about what exists.
    List<PatchObjectDescriptor> catalogue() => gateway.objectTypes();

    Finder box() => find.byKey(PatcherCanvas.inlineCreateKey);
    Finder field() => find.byKey(PatchInlineObjectBox.fieldKey);

    /// Two movement-free clicks at the same point — the pairing the canvas
    /// reads out of its own pointer stream, no recogniser involved.
    Future<void> doubleClickAt(WidgetTester tester, Offset at) async {
      await tester.tapAt(at);
      await tester.pump();
      await tester.tapAt(at);
      await tester.pump();
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(field(), text);
      await tester.pump();
    }

    testWidgets('two movement-free clicks on empty canvas open the box, at the '
        'point they landed on', (tester) async {
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
      );

      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));

      expect(box(), findsOneWidget);
      // It sits *in the scene* where the click did, so the object shows up
      // where it was asked for rather than at some anchored corner.
      expect(
        tester.getTopLeft(find.byType(PatchInlineObjectBox)),
        canvasTL(tester) + const Offset(300, 200),
      );
    });

    testWidgets('the box opens holding the keyboard, so the name is typed '
        'straight away', (tester) async {
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
      );

      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));
      await tester.pump();

      // The canvas takes focus on the very release that opens the box, so the
      // box has to take it back — an `autofocus` is skipped when the scope
      // already has a focused descendant, and the box would then come up with
      // the canvas still holding the keys: the first letters of the name would
      // run canvas shortcuts (`d` duplicates the selection) instead of typing.
      expect(
        tester.widget<TextField>(field()).focusNode!.hasPrimaryFocus,
        isTrue,
      );
    });

    testWidgets('one click opens nothing', (tester) async {
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
      );

      await tester.tapAt(canvasTL(tester) + const Offset(300, 200));
      await tester.pump();

      expect(box(), findsNothing);
    });

    testWidgets('two clicks far apart are two clicks, not a double-click', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
      );
      final tl = canvasTL(tester);

      await tester.tapAt(tl + const Offset(300, 200));
      await tester.pump();
      // Past `kDoubleTapSlop` (100px): clicking two different places is two
      // deselects, not a request to make an object.
      await tester.tapAt(tl + const Offset(300, 340));
      await tester.pump();

      expect(box(), findsNothing);
    });

    testWidgets('a marquee between two clicks never pairs into a box', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
      );
      final tl = canvasTL(tester);

      await tester.tapAt(tl + const Offset(300, 200));
      await tester.pump();
      final g = await tester.startGesture(tl + const Offset(300, 200));
      await tester.pump();
      await g.moveTo(tl + const Offset(380, 280));
      await tester.pump();
      await g.up();
      await tester.pump();
      await tester.tapAt(tl + const Offset(300, 200));
      await tester.pump();

      // A press that moved is a marquee, and it invalidates the click before it
      // (the `_resetGesture` discipline of issue #355) — so click → drag →
      // click can never sneak a box open mid-selection.
      expect(box(), findsNothing);
    });

    testWidgets('a double-click on a node is still the node double-click', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      PatchNode? doubleClicked;
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
        onNodeDoubleTap: (n) => doubleClicked = n,
      );

      await doubleClickAt(tester, nodeCenter(tester, sine));

      // Empty canvas makes objects, a node opens its parameters: one pairing
      // mechanism, two destinations, never both at once.
      expect(doubleClicked?.id, sine.id);
      expect(box(), findsNothing);
    });

    testWidgets('a press inside the box belongs to its field, not the canvas', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) {},
      );
      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));

      await tester.tapAt(tester.getCenter(field()));
      await tester.pump();
      await tester.pump();

      // The canvas neither dismisses the box nor takes the keyboard back on
      // release — the caret stays where it was clicked (issue #353's rule).
      expect(box(), findsOneWidget);
      expect(
        tester.widget<TextField>(field()).focusNode!.hasPrimaryFocus,
        isTrue,
      );
    });

    testWidgets('type a name and arguments, Enter creates it there — and '
        'Ctrl+Z takes it back', (tester) async {
      PatchObjectDescriptor? made;
      Offset? madeAt;
      String? madeArgs;
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (d, at, {args}) {
          made = d;
          madeAt = at;
          madeArgs = args;
          // What the surface does with the report — journaled, so the gesture
          // is undoable like every other canvas verb.
          controller.createObject(desc: d, position: at, args: args);
        },
      );

      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));
      await type(tester, 'sine 220');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // The acceptance gesture: `~sine` was never typed in full, and the `220`
      // arrived as its creation argument.
      expect(made?.type, Obj.dSine);
      expect(madeAt, const Offset(300, 200));
      expect(madeArgs, '220');
      expect(box(), findsNothing);
      expect(controller.graph.nodes, hasLength(1));
      expect(controller.graph.nodes.single.position, const Offset(300, 200));
      expect(controller.argsOf(controller.graph.nodes.single.id), '220');

      // Focus came back to the canvas with the box, so the undo is one
      // keystroke away — the whole point of a path the hands never leave.
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(controller.graph.nodes, isEmpty);
    });

    testWidgets('Escape dismisses and leaves the canvas untouched', (
      tester,
    ) async {
      var creates = 0;
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) => creates++,
      );
      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));
      await type(tester, 'sine 220');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(box(), findsNothing);
      expect(creates, 0);
      expect(controller.graph.nodes, isEmpty);
      // Not even an empty step on the stack: an abandoned gesture is no gesture.
      expect(controller.undoScope.canUndo, isFalse);
    });

    testWidgets('an unknown name keeps the box open for correction', (
      tester,
    ) async {
      var creates = 0;
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) => creates++,
      );
      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));
      await type(tester, 'zzzz');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(creates, 0);
      expect(box(), findsOneWidget);
      expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);

      // A typo costs a keystroke, not the gesture: fix it in place and go.
      await type(tester, 'sine');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(creates, 1);
      expect(box(), findsNothing);
    });

    testWidgets('a press elsewhere on the canvas abandons the box', (
      tester,
    ) async {
      var creates = 0;
      await pumpCanvas(
        tester,
        objectTypes: catalogue(),
        onCreateObject: (_, _, {args}) => creates++,
      );
      final tl = canvasTL(tester);
      await doubleClickAt(tester, tl + const Offset(300, 200));
      expect(box(), findsOneWidget);

      await tester.tapAt(tl + const Offset(650, 480));
      await tester.pump();

      // Clicking away is Escape by another route — nothing made, nothing left
      // stranded on the canvas.
      expect(box(), findsNothing);
      expect(creates, 0);
    });

    testWidgets('without a catalogue there is nothing to complete, so nothing '
        'opens', (tester) async {
      await pumpCanvas(tester, onCreateObject: (_, _, {args}) {});

      await doubleClickAt(tester, canvasTL(tester) + const Offset(300, 200));

      expect(box(), findsNothing);
    });
  });

  // ─── cursors + hover affordances (issue #359) ───────────────────────────
  // The canvas's hit zones were invisible: 8px port dots with nothing to say
  // they were ports, and node chrome that gave no sign it could be dragged.

  group('cursor and hover affordances', () {
    testWidgets('a hovered port is ringed and takes the crosshair', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      expect(find.byKey(PatcherCanvas.portHoverKey), findsNothing);

      final g = await mouse(tester);
      await g.moveTo(portGlobal(tester, sine, PatchPortSide.input, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(PatcherCanvas.portHoverKey), findsOneWidget);
      expect(activeCursor(), SystemMouseCursors.precise);

      // ...and both go away again when the pointer moves off.
      await g.moveTo(canvasTL(tester) + const Offset(620, 460));
      await tester.pumpAndSettle();
      expect(find.byKey(PatcherCanvas.portHoverKey), findsNothing);
      expect(activeCursor(), SystemMouseCursors.basic);
    });

    testWidgets('in edit mode every node takes the move cursor, GUI body and '
        'all', (tester) async {
      NodeTypeRegistry.instance.register(desc(Obj.gSlider));
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(200, 200),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(400, 200),
      );
      await pumpCanvas(tester);
      final g = await mouse(tester);

      // A plain node is draggable anywhere on it.
      await g.moveTo(nodeCenter(tester, sine));
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.move);

      // ...and so is a GUI node, now that its body is inert (issue #378):
      // there is no header left to point at instead.
      await g.moveTo(nodeCenter(tester, slider));
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.move);
    });

    testWidgets('a cable takes the pointer cursor, and the grab cursor near '
        'its ends', (tester) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      controller.connect(out(slider, 0), inp(sine, 0));
      await pumpCanvas(tester);

      final a = portPositionsFor(slider)[out(slider, 0)]!;
      final b = portPositionsFor(sine)[inp(sine, 0)]!;
      final g = await mouse(tester);

      await g.moveTo(canvasTL(tester) + PatchCableGeometry.pointAt(a, b, 0.5));
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.click);

      // Near an end the same wire offers something else: a grab, because that
      // is where it detaches.
      await g.moveTo(canvasTL(tester) + grabPoint(a, b, atSource: false));
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.grab);
    });
  });

  // ─── cable ergonomics (issue #359) ──────────────────────────────────────

  group('cables from either end', () {
    testWidgets('a cable dragged backwards from an inlet connects; undo '
        'disconnects', (tester) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      await pumpCanvas(tester);

      // Press the *inlet* and drag back to the outlet — the Max habit.
      final g = await tester.startGesture(
        portGlobal(tester, sine, PatchPortSide.input, 0),
      );
      await tester.pump();
      expect(controller.graph.dragSourcePort, inp(sine, 0));
      expect(find.byType(PatcherGhostCable), findsOneWidget);

      await g.moveTo(portGlobal(tester, slider, PatchPortSide.output, 0));
      await tester.pump();
      await g.up();
      await tester.pump();

      // Stored the one way round a cable is ever stored, whichever end it was
      // dragged from.
      expect(controller.graph.cables, hasLength(1));
      expect(controller.graph.cables.single.source, out(slider, 0));
      expect(controller.graph.cables.single.target, inp(sine, 0));
      expect(gateway.cables, hasLength(1));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(controller.graph.cables, isEmpty);
    });

    testWidgets('a backwards drag onto an incompatible outlet is rejected', (
      tester,
    ) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final dac = controller.addNode(
        desc: desc(Obj.dDac),
        position: const Offset(320, 120),
      );
      await pumpCanvas(tester);

      final g = await tester.startGesture(
        portGlobal(tester, dac, PatchPortSide.input, 0),
      );
      await tester.pump();
      await g.moveTo(portGlobal(tester, slider, PatchPortSide.output, 0));
      await tester.pump();
      await g.up();
      await tester.pump();

      // Same verdict as the forward drag reaches: float → DSP inlet is refused.
      expect(controller.graph.cables, isEmpty);
      expect(find.byKey(PatcherCanvas.rejectKey), findsOneWidget);
    });

    testWidgets('grabbing a cable near its inlet re-routes it in one journaled '
        'step', (tester) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      final other = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 300),
      );
      controller.connect(out(slider, 0), inp(sine, 0));
      await pumpCanvas(tester);

      final a = portPositionsFor(slider)[out(slider, 0)]!;
      final b = portPositionsFor(sine)[inp(sine, 0)]!;
      final g = await tester.startGesture(
        canvasTL(tester) + grabPoint(a, b, atSource: false),
      );
      await tester.pump();
      await g.moveTo(portGlobal(tester, other, PatchPortSide.input, 0));
      await tester.pump();

      // Detached: the wire is off while it is being carried, and hangs off the
      // end that stayed put.
      expect(controller.graph.cables, isEmpty);
      expect(controller.graph.dragSourcePort, out(slider, 0));

      await g.up();
      await tester.pump();

      expect(controller.graph.cables, hasLength(1));
      expect(controller.graph.cables.single.target, inp(other, 0));
      expect(gateway.cables, hasLength(1));

      // One step, not two: a single undo restores the original wire whole.
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(controller.graph.cables, hasLength(1));
      expect(controller.graph.cables.single.target, inp(sine, 0));
      expect(controller.undoScope.canUndo, isFalse);
    });

    testWidgets('a re-route dropped on nothing deletes the cable, journaled', (
      tester,
    ) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      controller.connect(out(slider, 0), inp(sine, 0));
      await pumpCanvas(tester);

      final a = portPositionsFor(slider)[out(slider, 0)]!;
      final b = portPositionsFor(sine)[inp(sine, 0)]!;
      final g = await tester.startGesture(
        canvasTL(tester) + grabPoint(a, b, atSource: true),
      );
      await tester.pump();
      // Grabbed at the outlet end, so the inlet is what stays anchored.
      await g.moveTo(canvasTL(tester) + const Offset(600, 420));
      await tester.pump();
      expect(controller.graph.dragSourcePort, inp(sine, 0));

      await g.up();
      await tester.pump();

      expect(controller.graph.cables, isEmpty);
      expect(gateway.cables, isEmpty);

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(controller.graph.cables, hasLength(1));
      expect(gateway.cables, hasLength(1));
    });

    testWidgets('a click near a cable end selects it and leaves it wired', (
      tester,
    ) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      controller.connect(out(slider, 0), inp(sine, 0));
      await pumpCanvas(tester);

      final a = portPositionsFor(slider)[out(slider, 0)]!;
      final b = portPositionsFor(sine)[inp(sine, 0)]!;
      await tester.tapAt(canvasTL(tester) + grabPoint(a, b, atSource: false));
      await tester.pump();

      // A press that never travelled is a click, not a detach — the wire is
      // still there, and it is what Delete would now act on.
      expect(controller.graph.cables, hasLength(1));
      expect(controller.graph.selectedCable, isNotNull);
      expect(controller.reroutingCable, isNull);
      expect(controller.undoScope.canUndo, isFalse);
    });

    testWidgets('a press on the port dot itself still starts a new cable, not '
        'a re-route', (tester) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      final other = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 300),
      );
      controller.connect(out(slider, 0), inp(sine, 0));
      await pumpCanvas(tester);

      final g = await tester.startGesture(
        portGlobal(tester, slider, PatchPortSide.output, 0),
      );
      await tester.pump();
      await g.moveTo(portGlobal(tester, other, PatchPortSide.input, 0));
      await tester.pump();
      // The existing cable is untouched: pressing the dot means "another one".
      expect(controller.graph.cables, hasLength(1));
      expect(controller.reroutingCable, isNull);

      await g.up();
      await tester.pump();
      expect(controller.graph.cables, hasLength(2));
    });
  });

  // ─── view navigation: space-hold pan + Ctrl+0 (issue #369) ───────────────
  //
  // Both are *modes over* the gesture pipeline rather than gestures of their
  // own, so what these cases are really about is the seams: that arming the
  // mode does not cost the canvas its plain left-drag, that the mode cannot
  // outlive the key or the focus that armed it, and that the frame lands
  // somewhere defensible.

  group('space-hold pan', () {
    /// Give the canvas the keyboard the way a user does — a click on empty
    /// canvas, which is the only path that takes focus.
    Future<void> focusCanvas(WidgetTester tester) async {
      await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
      await tester.pump();
    }

    Future<void> spaceDown(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump();
    }

    Future<void> spaceUp(WidgetTester tester) async {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();
    }

    double panX() => controller.transform.value.getTranslation().x;
    double panY() => controller.transform.value.getTranslation().y;

    testWidgets('space held, a left-drag pans the view', (tester) async {
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);

      await spaceDown(tester);
      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(400, 400));
      await tester.pump();
      await g.moveBy(const Offset(-20, -10));
      await tester.pump();

      expect(panX(), -20);
      expect(panY(), -10);
      // A pan is not a selection gesture: nothing was marqueed on the way.
      expect(find.byKey(PatcherCanvas.marqueeKey), findsNothing);
      expect(controller.graph.selectedNodes, isEmpty);

      await g.up();
      await tester.pump();
      await spaceUp(tester);
      expect(panX(), -20);
    });

    testWidgets('space held, a press over a node pans instead of dragging it', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);
      await spaceDown(tester);

      final g = await tester.startGesture(nodeCenter(tester, sine));
      await tester.pump();
      await g.moveBy(const Offset(30, 20));
      await tester.pump();
      await g.up();
      await tester.pump();

      // The node stayed put in the model — the scene moved under it instead.
      expect(sine.position, const Offset(120, 120));
      expect(controller.undoScope.canUndo, isFalse);
      expect(panX(), 30);
      expect(panY(), 20);
    });

    testWidgets('without space a left-drag still marquees', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);

      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(40, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(240, 300));
      await tester.pump();
      expect(find.byKey(PatcherCanvas.marqueeKey), findsOneWidget);
      await g.up();
      await tester.pump();

      expect(controller.graph.selectedNodes, {sine.id});
      expect(panX(), 0);
      expect(panY(), 0);
    });

    testWidgets('releasing space mid-drag ends the pan there and then, and '
        'strands nothing', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);
      await spaceDown(tester);

      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(400, 400));
      await tester.pump();
      await g.moveBy(const Offset(-20, -10));
      await tester.pump();
      expect(panX(), -20);

      // Space goes up while the pointer is still down.
      await spaceUp(tester);
      await g.moveBy(const Offset(-50, -50));
      await tester.pump();
      // The pan stopped with the key: the rest of the drag moves nothing.
      expect(panX(), -20);
      expect(panY(), -10);

      await g.up();
      await tester.pump();
      // …and the release of an abandoned pan is not a click either: it neither
      // marquees nor clears anything.
      expect(find.byKey(PatcherCanvas.marqueeKey), findsNothing);

      // Nothing was left armed: the very next left-drag marquees again.
      controller.transform.value = Matrix4.identity();
      await tester.pump();
      final g2 = await tester.startGesture(tl + const Offset(40, 60));
      await tester.pump();
      await g2.moveTo(tl + const Offset(240, 300));
      await tester.pump();
      await g2.up();
      await tester.pump();
      expect(controller.graph.selectedNodes, {sine.id});
      expect(panX(), 0);
    });

    testWidgets('space while a number field holds the keyboard never pans', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      controller.addNode(desc: numberDesc(), position: const Offset(120, 120));
      // The field is live in run mode (issue #378), which is how it comes to
      // hold the keyboard at all; the canvas is put back into edit mode
      // afterwards, so the drag below is the plain marquee it always was.
      await pumpCanvas(tester, initialMode: PatchCanvasMode.run);

      await tester.tapAt(tester.getCenter(find.byType(TextField)));
      await tester.pump();
      await tester.pump();
      expect(fieldFocus(tester).hasPrimaryFocus, isTrue);
      await setMode(tester, PatchCanvasMode.edit);
      expect(fieldFocus(tester).hasPrimaryFocus, isTrue);

      // The space belongs to the field being typed into (issue #353), so the
      // canvas must not quietly arm a pan behind it.
      await spaceDown(tester);
      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(240, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(440, 300));
      await tester.pump();
      await g.up();
      await tester.pump();
      await spaceUp(tester);

      expect(panX(), 0);
      expect(panY(), 0);
      // It marqueed instead, which is what a left-drag on empty canvas means.
      expect(controller.graph.selectedNodes, {sine.id});
    });

    testWidgets('a space released while the keyboard is elsewhere leaves '
        'nothing armed', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      controller.addNode(desc: numberDesc(), position: const Offset(120, 120));
      await pumpCanvas(tester);
      await focusCanvas(tester);
      await spaceDown(tester);

      // The keyboard moves to the number box while space is still down, so the
      // key-up lands there and the canvas never sees it. Nothing may survive
      // that: the mode has to expire with the key, not with the event.
      // (Run mode is what makes the field pressable; the canvas goes straight
      // back to edit, where the drag below is the plain marquee it always was.)
      await setMode(tester, PatchCanvasMode.run);
      await tester.tapAt(tester.getCenter(find.byType(TextField)));
      await tester.pump();
      await tester.pump();
      expect(fieldFocus(tester).hasPrimaryFocus, isTrue);
      await spaceUp(tester);
      await setMode(tester, PatchCanvasMode.edit);

      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(240, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(440, 300));
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(panX(), 0);
      expect(controller.graph.selectedNodes, {sine.id});
    });

    testWidgets('a space released mid-drag ends the pan even when its key-up '
        'went somewhere else', (tester) async {
      // In the real shell the enclosing pane grabs the keyboard on *every*
      // pointer-down, so the release of a space held through a drag lands
      // there and never reaches the canvas at all. A neighbouring focus node
      // stands in for the pane here.
      final elsewhere = FocusNode(debugLabel: 'elsewhere');
      addTearDown(elsewhere.dispose);
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: elsewhere, child: const SizedBox(height: 1)),
                Expanded(child: PatcherCanvas(controller: controller)),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final tl = canvasTL(tester);
      await tester.tapAt(tl + const Offset(600, 400));
      await tester.pump();
      await spaceDown(tester);

      final g = await tester.startGesture(tl + const Offset(400, 300));
      await tester.pump();
      await g.moveBy(const Offset(-20, -10));
      await tester.pump();
      expect(panX(), -20);

      // The keyboard moves away, then the key comes up — so no key event ever
      // tells the canvas the mode is over.
      elsewhere.requestFocus();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pump();

      await g.moveBy(const Offset(-50, -50));
      await tester.pump();
      expect(panX(), -20);
      expect(panY(), -10);

      await g.up();
      await tester.pump();
    });

    testWidgets('the cursor is an open hand while space is held and a closed '
        'one while panning', (tester) async {
      await pumpCanvas(tester);
      final tl = canvasTL(tester);
      final at = tl + const Offset(400, 400);
      final m = await mouse(tester);

      await m.moveTo(at);
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.basic);

      // A click is how the canvas comes to hold the keyboard.
      await m.down(at);
      await tester.pump();
      await m.up();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.grab);

      await m.down(at);
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.grabbing);

      await m.moveBy(const Offset(-20, -10));
      await tester.pumpAndSettle();
      await m.up();
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.grab);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.basic);
    });

    testWidgets('a cancelled space pan does not swallow the next gesture', (
      tester,
    ) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);
      await spaceDown(tester);

      final tl = canvasTL(tester);
      final pan = await tester.startGesture(tl + const Offset(400, 400));
      await tester.pump();
      await pan.moveBy(const Offset(-20, -10));
      await tester.pump();
      await pan.cancel();
      await tester.pump();
      await spaceUp(tester);

      controller.transform.value = Matrix4.identity();
      await tester.pump();
      final g = await tester.startGesture(tl + const Offset(40, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(240, 300));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(controller.graph.selectedNodes, {sine.id});
    });
  });

  // ─── Ctrl+0 frames the patch (issue #369) ───────────────────────────────

  group('Ctrl+0 frames the patch', () {
    /// Where a scene point lands in the viewport under the current view.
    Offset onScreen(Offset scene) =>
        MatrixUtils.transformPoint(controller.transform.value, scene);

    /// The view's zoom, read straight off the x axis. Deliberately **not**
    /// `Matrix4.getMaxScaleOnAxis`, which maxes over all three axes and so
    /// reports 1.0 for any 2-D matrix zoomed *out* — the untouched z column
    /// wins — and would quietly pass a fit that never happened.
    double viewScale() => controller.transform.value.entry(0, 0);

    Future<void> focusCanvas(WidgetTester tester) async {
      await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
      await tester.pump();
    }

    testWidgets('from anywhere, it centres the graph at 1:1', (tester) async {
      // Bounds (120,120)–(400,360); padded by 40 that is (80,80)–(440,400),
      // 360×320 inside an 800×600 viewport — so nothing has to shrink.
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 300),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);

      // Lost: panned far off the patch and zoomed in on nothing.
      controller.transform.value = Matrix4.identity()
        ..translateByDouble(-1400, -900, 0, 1)
        ..scaleByDouble(2, 2, 1, 1);
      await tester.pump();

      await ctrl(tester, LogicalKeyboardKey.digit0);

      expect(viewScale(), 1.0);
      // The padded bounds' centre (260, 240) sits at the viewport's (400, 300).
      expect(controller.transform.value.getTranslation().x, 140);
      expect(controller.transform.value.getTranslation().y, 60);
      expect(onScreen(const Offset(260, 240)), const Offset(400, 300));
    });

    testWidgets('a graph wider than the viewport is zoomed out to fit', (
      tester,
    ) async {
      controller.addNode(desc: desc(Obj.dSine), position: Offset.zero);
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(1500, 1000),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);

      await ctrl(tester, LogicalKeyboardKey.digit0);

      // Padded bounds are 1660×1140; the width is the binding constraint.
      expect(viewScale(), closeTo(800 / 1660, 1e-9));

      // Every corner of the graph is on screen, which is the whole claim.
      for (final corner in [
        Offset.zero,
        const Offset(1580, 0),
        const Offset(0, 1060),
        const Offset(1580, 1060),
      ]) {
        final p = onScreen(corner);
        expect(p.dx, inInclusiveRange(0, 800));
        expect(p.dy, inInclusiveRange(0, 600));
      }
    });

    testWidgets('on an empty canvas it is the identity view', (tester) async {
      await pumpCanvas(tester);
      await focusCanvas(tester);
      controller.transform.value = Matrix4.identity()
        ..translateByDouble(-320, 180, 0, 1)
        ..scaleByDouble(0.5, 0.5, 1, 1);
      await tester.pump();

      await ctrl(tester, LogicalKeyboardKey.digit0);
      expect(controller.transform.value, Matrix4.identity());
    });

    testWidgets('it stays out of the way while a number field has the '
        'keyboard', (tester) async {
      controller.addNode(desc: numberDesc(), position: const Offset(120, 120));
      // Run mode, the only one in which a number field can hold the keyboard
      // at all (issue #378) — and `Ctrl+0` is a navigation key, so it is live
      // in that mode too, which is exactly what this guards.
      await pumpCanvas(tester, initialMode: PatchCanvasMode.run);

      await tester.tapAt(tester.getCenter(find.byType(TextField)));
      await tester.pump();
      await tester.pump();
      expect(fieldFocus(tester).hasPrimaryFocus, isTrue);

      final moved = Matrix4.identity()..translateByDouble(-320, 180, 0, 1);
      controller.transform.value = moved.clone();
      await tester.pump();

      await ctrl(tester, LogicalKeyboardKey.digit0);
      expect(controller.transform.value, moved);
    });
  });

  // ─── the wheel zoom is held inside its range (issue #373) ────────────────

  group('wheel zoom clamp', () {
    /// The view's zoom, read off the x basis. Deliberately **not**
    /// `Matrix4.getMaxScaleOnAxis` — that is the bug under test: it maxes over
    /// all three axes, and the canvas leaves z at unity, so it reports `1.0`
    /// for every zoomed-*out* view and would mask exactly what is asserted
    /// here.
    double viewScale() => controller.transform.value.entry(0, 0);

    /// [times] wheel notches at the middle of the canvas. Negative [dy] is
    /// wheel-up, which zooms in.
    Future<void> wheel(WidgetTester tester, double dy, {int times = 1}) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(canvasTL(tester) + const Offset(400, 300));
      for (var i = 0; i < times; i++) {
        await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
        await tester.pump();
      }
    }

    testWidgets('wheeling down stops at the 0.25 floor and stays there', (
      tester,
    ) async {
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);

      // Far more notches than the 15 that reach the floor from 1:1, so an
      // unclamped view would have shrunk the patch away to nothing.
      await wheel(tester, 100, times: 40);
      expect(viewScale(), closeTo(0.25, 1e-9));

      // The floor is terminal, not merely a value passed through: more of the
      // same gesture leaves the view untouched.
      final atFloor = controller.transform.value.clone();
      await wheel(tester, 100, times: 5);
      expect(controller.transform.value, atFloor);

      // And the way back is measured from where the view really is: three
      // notches up from the floor is the floor times 1.1³, not three notches
      // up from wherever an unclamped shrink had run off to.
      await wheel(tester, -100, times: 3);
      expect(viewScale(), closeTo(0.25 * math.pow(1.1, 3), 1e-9));
    });

    testWidgets('wheeling back up returns through the same scales', (
      tester,
    ) async {
      await pumpCanvas(tester);

      final down = <double>[];
      for (var i = 0; i < 5; i++) {
        await wheel(tester, 100);
        down.add(viewScale());
      }
      expect(down.last, closeTo(math.pow(1 / 1.1, 5).toDouble(), 1e-9));

      for (final expected in down.reversed.skip(1)) {
        await wheel(tester, -100);
        expect(viewScale(), closeTo(expected, 1e-9));
      }
      await wheel(tester, -100);
      expect(viewScale(), closeTo(1.0, 1e-9));
    });

    testWidgets('wheeling up stops at the 4.0 ceiling', (tester) async {
      await pumpCanvas(tester);

      await wheel(tester, -100, times: 40);
      expect(viewScale(), closeTo(4.0, 1e-9));

      final atCeiling = controller.transform.value.clone();
      await wheel(tester, -100, times: 5);
      expect(controller.transform.value, atCeiling);
    });

    testWidgets('the point under the cursor stays put on the way out', (
      tester,
    ) async {
      await pumpCanvas(tester);
      final anchor = canvasTL(tester) + const Offset(400, 300);
      final scene = MatrixUtils.transformPoint(
        Matrix4.inverted(controller.transform.value),
        anchor - canvasTL(tester),
      );

      await wheel(tester, 100, times: 40);

      final after =
          canvasTL(tester) +
          MatrixUtils.transformPoint(controller.transform.value, scene);
      expect(after.dx, closeTo(anchor.dx, 1e-6));
      expect(after.dy, closeTo(anchor.dy, 1e-6));
    });
  });

  // ─── edit / run mode (issue #378) ────────────────────────────────────────
  //
  // The mode is what replaces "drag a GUI node by its header", so the cases
  // that matter are the ones where the two modes *disagree* about who owns a
  // press — and the ones where they must agree, because navigating is not
  // editing.

  group('edit / run mode', () {
    /// Whether the live body under the pointer saw the gesture at all.
    late bool bodyDragged;
    late bool bodyPressed;

    /// A GUI node whose body reports every press it receives. Registered as
    /// well as returned: the canvas renders bodies out of the registry.
    NodeDescriptor liveDesc() {
      final d = desc(
        Obj.gSlider,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => bodyPressed = true,
          onPanStart: (_) => bodyDragged = true,
          child: const SizedBox.expand(),
        ),
      );
      NodeTypeRegistry.instance.register(d);
      return d;
    }

    setUp(() {
      bodyDragged = false;
      bodyPressed = false;
    });

    /// Give the canvas the keyboard the way a user does — a click on empty
    /// canvas, which takes focus in both modes so `Ctrl+E` is always reachable.
    Future<void> focusCanvas(WidgetTester tester) async {
      await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
      await tester.pump();
    }

    /// `Ctrl` + the key in the given *position*, with whatever glyph that
    /// position reports on the layout being simulated.
    Future<void> ctrlAt(
      WidgetTester tester,
      PhysicalKeyboardKey physical,
      LogicalKeyboardKey logical,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(logical, physicalKey: physical);
      await tester.sendKeyUpEvent(logical, physicalKey: physical);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('edit mode: a press on a live GUI body drags its node and '
        'never reaches the body', (tester) async {
      final slider = controller.addNode(
        desc: liveDesc(),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);

      final g = await tester.startGesture(nodeCenter(tester, slider));
      await tester.pump();
      await g.moveBy(const Offset(30, 20));
      await tester.pump();
      await g.up();
      await tester.pump();

      // The whole point of the mode: with no header left to grab, the fader
      // itself is what the node is dragged by.
      expect(slider.position, const Offset(150, 140));
      expect(bodyDragged, isFalse);
      expect(bodyPressed, isFalse);
    });

    testWidgets('edit mode: a marquee sweeps a GUI node up like any other', (
      tester,
    ) async {
      final slider = controller.addNode(
        desc: liveDesc(),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);

      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(60, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(300, 300));
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(controller.graph.selectedNodes, {slider.id});
      expect(bodyDragged, isFalse);
    });

    testWidgets('run mode: the same press operates the body, and the node '
        'neither moves nor selects', (tester) async {
      final slider = controller.addNode(
        desc: liveDesc(),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester, initialMode: PatchCanvasMode.run);

      final g = await tester.startGesture(nodeCenter(tester, slider));
      await tester.pump();
      await g.moveBy(const Offset(30, 20));
      await tester.pump();
      await g.up();
      await tester.pump();

      expect(bodyDragged, isTrue);
      expect(slider.position, const Offset(120, 120));
      expect(controller.graph.selectedNodes, isEmpty);
      expect(controller.undoScope.canUndo, isFalse);
    });

    testWidgets('run mode: a marquee neither draws nor selects', (
      tester,
    ) async {
      controller.addNode(desc: liveDesc(), position: const Offset(120, 120));
      await pumpCanvas(tester, initialMode: PatchCanvasMode.run);

      final tl = canvasTL(tester);
      final g = await tester.startGesture(tl + const Offset(60, 60));
      await tester.pump();
      await g.moveTo(tl + const Offset(300, 300));
      await tester.pump();
      expect(find.byKey(PatcherCanvas.marqueeKey), findsNothing);
      await g.up();
      await tester.pump();

      expect(controller.graph.selectedNodes, isEmpty);
    });

    testWidgets('run mode: a press on a port starts no cable and a '
        'right-click opens no menu', (tester) async {
      final slider = controller.addNode(
        desc: desc(Obj.gSlider),
        position: const Offset(100, 120),
      );
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(320, 120),
      );
      PatchNode? menuFor;
      await pumpCanvas(
        tester,
        initialMode: PatchCanvasMode.run,
        onNodeContextMenu: (n, _) => menuFor = n,
      );

      final g = await tester.startGesture(
        portGlobal(tester, slider, PatchPortSide.output, 0),
      );
      await tester.pump();
      expect(controller.graph.dragSourcePort, isNull);
      await g.moveTo(portGlobal(tester, sine, PatchPortSide.input, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(controller.graph.cables, isEmpty);

      await rightClickAt(tester, nodeCenter(tester, sine));
      expect(menuFor, isNull);
    });

    testWidgets('run mode: Delete, Ctrl+D and the arrows leave the graph '
        'alone', (tester) async {
      final sine = controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      // Selected from edit mode, so the keys below have a target — the mode is
      // what declines them, not an empty selection.
      await pumpCanvas(tester);
      await tester.tapAt(nodeCenter(tester, sine));
      await tester.pump();
      expect(controller.graph.selectedNodes, {sine.id});

      await setMode(tester, PatchCanvasMode.run);
      await focusCanvas(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(sine.position, const Offset(120, 120));

      await ctrl(tester, LogicalKeyboardKey.keyD);
      expect(controller.graph.nodes, hasLength(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(controller.graph.nodes, hasLength(1));

      // Undo is an edit too: a played patch is not rearranged by a mistyped
      // chord.
      controller.placeNode(sine.id, const Offset(200, 200));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, const Offset(200, 200));
    });

    testWidgets('run mode: pan, wheel zoom and Ctrl+0 still answer', (
      tester,
    ) async {
      controller.addNode(
        desc: desc(Obj.dSine),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester, initialMode: PatchCanvasMode.run);
      await focusCanvas(tester);

      // Middle-drag pans.
      final g = await tester.startGesture(
        canvasTL(tester) + const Offset(400, 400),
        buttons: kMiddleMouseButton,
      );
      await tester.pump();
      await g.moveBy(const Offset(-20, -10));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(controller.transform.value.getTranslation().x, -20);

      // The wheel zooms.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(canvasTL(tester) + const Offset(400, 300));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
      expect(controller.transform.value.entry(0, 0), closeTo(1.1, 1e-9));

      // And Ctrl+0 frames the patch from wherever that left it.
      await ctrl(tester, LogicalKeyboardKey.digit0);
      expect(controller.transform.value.entry(0, 0), 1.0);
    });

    testWidgets('Ctrl+E flips the mode, read from the key position rather '
        'than its glyph', (tester) async {
      final slider = controller.addNode(
        desc: liveDesc(),
        position: const Offset(120, 120),
      );
      await pumpCanvas(tester);
      await focusCanvas(tester);
      expect(mode, PatchCanvasMode.edit);

      // A layout that reports something else for the key in `E`'s position:
      // the *position* is the habit, exactly as for `Ctrl+0` (issue #369).
      await ctrlAt(tester, PhysicalKeyboardKey.keyE, LogicalKeyboardKey.keyJ);
      expect(mode, PatchCanvasMode.run);

      // ...and the mode really took: the body now owns the press.
      await tester.tapAt(nodeCenter(tester, slider));
      await tester.pump();
      expect(bodyPressed, isTrue);
      expect(controller.graph.selectedNodes, isEmpty);

      // Back again, this time from the ordinary QWERTY glyph.
      await focusCanvas(tester);
      await ctrl(tester, LogicalKeyboardKey.keyE);
      expect(mode, PatchCanvasMode.edit);
    });

    testWidgets('Ctrl+E is left unhandled when the host holds no mode', (
      tester,
    ) async {
      await pumpCanvas(tester, toggleable: false);
      await focusCanvas(tester);

      await ctrl(tester, LogicalKeyboardKey.keyE);
      expect(mode, PatchCanvasMode.edit);
    });

    testWidgets('the cursor previews the mode it is in', (tester) async {
      final slider = controller.addNode(
        desc: liveDesc(),
        position: const Offset(200, 200),
      );
      await pumpCanvas(tester);
      final g = await mouse(tester);

      await g.moveTo(nodeCenter(tester, slider));
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.move);

      // In run mode the same pixel plays the object instead of moving it, so
      // the canvas promises nothing there and leaves the body to say what it
      // wants from deeper in the tree (design §6).
      await setMode(tester, PatchCanvasMode.run);
      await tester.pumpAndSettle();
      expect(activeCursor(), isNot(SystemMouseCursors.move));

      await setMode(tester, PatchCanvasMode.edit);
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.move);
    });
  });
}
