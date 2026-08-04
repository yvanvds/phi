import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
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
    void Function(PatchNode node)? onNodeDoubleTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PatcherCanvas(
            controller: controller,
            onNodeDoubleTap: onNodeDoubleTap,
          ),
        ),
      ),
    );
    await tester.pump();
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
}
