import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Drives the reworked patcher canvas (issue #222): body drag, typed cables,
/// marquee + shift-click, cable/node delete, duplicate — each with undo/redo,
/// exercised through real pointer + keyboard gestures.
void main() {
  NodeDescriptor desc(String type) => NodeDescriptor(
    type: type,
    title: type,
    defaultSize: const Size(80, 60),
    defaultArgs: '',
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => const SizedBox.shrink(),
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

  Future<void> pumpCanvas(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PatcherCanvas(controller: controller)),
      ),
    );
    await tester.pump();
  }

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

    // A stepped drag: the first move clears the touch slop (starts the drag),
    // subsequent moves shift the node down-right.
    final g = await tester.startGesture(nodeCenter(tester, sine));
    await tester.pump();
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(30, 25));
    await tester.pump();
    await g.up();
    await tester.pump();

    final moved = sine.position;
    expect(moved.dx, greaterThan(start.dx));
    expect(moved.dy, greaterThan(start.dy));

    // The drag focused the canvas, so Ctrl+Z reaches its undo scope; undo/redo
    // restore and re-apply the move exactly.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(sine.position, start);

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(sine.position, moved);
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
