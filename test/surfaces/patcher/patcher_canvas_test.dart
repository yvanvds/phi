import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
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
  NodeDescriptor desc(
    String type, {
    Widget? body,
    bool interactiveBody = false,
  }) => NodeDescriptor(
    type: type,
    title: type,
    defaultSize: const Size(80, 60),
    defaultArgs: '',
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => body ?? const SizedBox.shrink(),
    interactiveBody: interactiveBody,
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

  Future<void> pumpCanvas(
    WidgetTester tester, {
    List<PatchObjectDescriptor> objectTypes = const [],
    bool snapToGrid = false,
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatcherCanvas(
            controller: controller,
            objectTypes: objectTypes,
            snapToGrid: snapToGrid,
            onCreateObject: onCreateObject,
            onNodeTap: onNodeTap,
            onNodeDoubleTap: onNodeDoubleTap,
            onNodeContextMenu: onNodeContextMenu,
          ),
        ),
      ),
    );
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
  /// build.
  Offset frameTopLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PatchNodeFrame));

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

  testWidgets('a press on a live GUI body operates the body, never the node', (
    tester,
  ) async {
    var bodyDragged = false;
    // The canvas renders bodies — and decides what owns a press — from the
    // registry, so this descriptor has to be registered, not just passed in.
    final live = desc(
      Obj.gSlider,
      interactiveBody: true,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => bodyDragged = true,
        child: const SizedBox.expand(),
      ),
    );
    NodeTypeRegistry.instance.register(live);
    final slider = controller.addNode(
      desc: live,
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);

    // Scene (150, 160) sits in the body, below the 22px header.
    final g = await tester.startGesture(
      canvasTL(tester) + const Offset(150, 160),
    );
    await tester.pump();
    await g.moveBy(const Offset(30, 20));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(bodyDragged, isTrue);
    expect(slider.position, const Offset(120, 120));
    expect(controller.graph.selectedNodes, isEmpty);
  });

  // ─── editable bodies keep focus and keys (issue #353) ───────────────────

  /// A real `.f` number node, registered as well as returned: the canvas reads
  /// both the body and the "this body owns the press" flag from the registry.
  NodeDescriptor numberDesc() {
    final d = NodeDescriptor(
      type: Obj.gFloat,
      title: Obj.gFloat,
      defaultSize: const Size(110, 70),
      defaultArgs: '',
      inputs: const [],
      outputs: const [],
      buildBody: (ctx, node, controller) =>
          NumberNodeBody(node: node, controller: controller),
      interactiveBody: true,
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
    await pumpCanvas(tester);

    await tester.tapAt(tester.getCenter(find.byType(TextField)));
    await tester.pump();
    await tester.pump();

    expect(fieldFocus(tester).hasPrimaryFocus, isTrue);
    // The press belonged to the body: no selection, no move.
    expect(controller.graph.selectedNodes, isEmpty);
    expect(number.position, const Offset(120, 120));

    // Scene (126, 146): inside the node's body rect (which starts 22px down,
    // below the header) but in the padding beside the readout, so no widget
    // claims it. The canvas must still keep its hands off the caret.
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
    await pumpCanvas(tester);

    // Select the sine — the canvas holds focus and Delete would remove it.
    await tester.tapAt(nodeCenter(tester, sine));
    await tester.pump();
    expect(controller.graph.selectedNodes, {sine.id});

    // Now edit the number box and rub out a digit.
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1',
    );
    // The selection survived untouched: the key belonged to the field.
    expect(controller.graph.nodes, hasLength(2));
    expect(controller.graph.selectedNodes, {sine.id});

    // And once the canvas has focus again, Delete still removes the selection.
    await tester.tapAt(canvasTL(tester) + const Offset(600, 500));
    await tester.pump();
    await tester.tapAt(nodeCenter(tester, sine));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(controller.graph.nodes, hasLength(1));
  });

  testWidgets('a press on the number node header still selects and drags it', (
    tester,
  ) async {
    final number = controller.addNode(
      desc: numberDesc(),
      position: const Offset(120, 120),
    );
    await pumpCanvas(tester);

    // Scene (170, 131): the middle of the 22px header.
    final g = await tester.startGesture(
      canvasTL(tester) + const Offset(170, 131),
    );
    await tester.pump();
    await g.moveBy(const Offset(30, 20));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(number.position, const Offset(150, 140));

    await tester.tapAt(canvasTL(tester) + const Offset(200, 161));
    await tester.pump();
    expect(controller.graph.selectedNodes, {number.id});
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
        title: '.fan',
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

    testWidgets('node chrome takes the move cursor; a live body does not', (
      tester,
    ) async {
      NodeTypeRegistry.instance.register(
        desc(Obj.gSlider, interactiveBody: true),
      );
      final slider = controller.addNode(
        desc: desc(Obj.gSlider, interactiveBody: true),
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

      // A live body belongs to the widget inside it, which is dragged by its
      // header — so the body says nothing and the header says move.
      await g.moveTo(nodeCenter(tester, slider));
      await tester.pumpAndSettle();
      expect(activeCursor(), SystemMouseCursors.basic);

      await g.moveTo(
        canvasTL(tester) +
            slider.position +
            Offset(
              slider.size.width / 2,
              PatchCanvasConstants.headerHeight / 2,
            ),
      );
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
}
