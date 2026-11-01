import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_function_graph.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/function_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the `.function` breakpoint editor (issue #475): each
/// gesture reaches the fake gateway as the message the object takes, and the
/// graph follows points driven from the graph through the per-cell poll.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  PatchNode addNode({String args = ''}) {
    final registered = NodeTypeRegistry.instance.find(Obj.gFunction)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: Obj.gFunction,
        defaultSize: registered.defaultSize,
        defaultArgs: args,
        inputs: registered.inputs,
        outputs: registered.outputs,
        buildBody: registered.buildBody,
        readsGuiValue: registered.readsGuiValue,
        guiValueRead: registered.guiValueRead,
      ),
      position: Offset.zero,
    );
  }

  int handle() => gateway.nodes.keys.single;
  List<List<double>> points() => [
    for (final c in gateway.nodes.values.single.guiCells)
      [for (final n in c.split(' ')) double.parse(n)],
  ];

  /// What reached the object's inlet 0, lists and messages alike.
  List<String> sent() => [
    for (final c in gateway.calls)
      for (final verb in const ['sendList', 'sendMessage'])
        if (c.startsWith('$verb:${handle()}:0:'))
          c.substring('$verb:${handle()}:0:'.length),
  ];

  PatchFunctionGraph graph(WidgetTester tester) =>
      tester.widget<PatchFunctionGraph>(find.byType(PatchFunctionGraph));

  Future<void> pumpBody(WidgetTester tester, PatchNode node) async {
    final size = node.size;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Builder(
                builder: (context) => NodeTypeRegistry.instance
                    .find(node.type)!
                    .buildBody!(context, node, controller),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The screen position of plot position ([x], [y]), both 0–1, y up.
  Offset plotAt(WidgetTester tester, double x, double y) {
    final box = tester.getRect(find.byType(PatchFunctionGraph));
    const inset = PatchFunctionGraph.inset;
    return box.topLeft +
        Offset(
          inset + x * (box.width - 2 * inset),
          inset + (1 - y) * (box.height - 2 * inset),
        );
  }

  void seed(String state) =>
      gateway.restoreGuiValue(controller.instanceId, handle(), state);

  test('registers as a per-cell GUI body with three outlets', () {
    final d = NodeTypeRegistry.instance.find(Obj.gFunction)!;
    expect(d.readsGuiValue, isTrue);
    expect(d.guiValueRead, GuiValueRead.cells);
    expect(d.defaultSize, const Size(200, 100));
    expect([for (final o in d.outputs) o.label], ['y', 'ramp', 'dump']);
  });

  testWidgets('draws the points over their domain and y range', (tester) async {
    final node = addNode(args: '16 0 10');
    seed('0 0 0 50 10 0.5 200 5 0');
    await pumpBody(tester, node);

    expect(find.byType(FunctionNodeBody), findsOneWidget);
    expect(graph(tester).positions, [(0.0, 0.0), (0.25, 1.0), (1.0, 0.5)]);
    expect(graph(tester).curves, [0, 0.5, 0]);
  });

  testWidgets('a click on empty space adds a point there', (tester) async {
    final node = addNode();
    await pumpBody(tester, node);
    gateway.calls.clear();

    await tester.tapAt(plotAt(tester, 0.5, 0.5));
    await tester.pumpAndSettle();
    expect(sent(), ['500 0.5']);
    expect(points(), [
      [500, 0.5, 0],
    ]);
    expect(graph(tester).positions, hasLength(1));
    expect(graph(tester).selected, 0);
  });

  testWidgets('a drag moves a point, keeping its curve', (tester) async {
    final node = addNode();
    seed('0 0 0 500 1 0.5 1000 0 0');
    await pumpBody(tester, node);
    gateway.calls.clear();

    final drag = await tester.startGesture(plotAt(tester, 0.5, 1));
    await drag.moveTo(plotAt(tester, 0.25, 0.5));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(sent().last, 'set 1 250 0.5');
    expect(points()[1], [250, 0.5, 0.5]);
    expect(graph(tester).positions[1], (0.25, 0.5));
  });

  testWidgets('an alt-drag on a segment bends its curve', (tester) async {
    final node = addNode();
    seed('0 0 0 500 1 0 1000 0 0');
    await pumpBody(tester, node);
    gateway.calls.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final at = plotAt(tester, 0.25, 0.3);
    final drag = await tester.startGesture(at);
    await drag.moveTo(at - const Offset(0, 50));
    await tester.pump();
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(sent(), ['setcurve 1 -0.5']);
    expect(points()[1], [500, 1, -0.5]);
    expect(graph(tester).curves[1], -0.5);
  });

  testWidgets('a double-click on a point removes it', (tester) async {
    final node = addNode();
    seed('0 0 0 500 1 0 1000 0 0');
    await pumpBody(tester, node);
    gateway.calls.clear();

    await tester.tapAt(plotAt(tester, 0.5, 1));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(plotAt(tester, 0.5, 1));
    await tester.pumpAndSettle();

    expect(sent(), ['clear 1']);
    expect(points(), [
      [0, 0, 0],
      [1000, 0, 0],
    ]);
    expect(graph(tester).positions, hasLength(2));
  });

  testWidgets('Delete removes the point a click took', (tester) async {
    final node = addNode();
    seed('0 0 0 500 1 0 1000 0 0');
    await pumpBody(tester, node);
    gateway.calls.clear();

    await tester.tapAt(plotAt(tester, 1, 0));
    await tester.pumpAndSettle();
    expect(sent(), isEmpty, reason: 'a click on a point writes nothing');
    expect(graph(tester).selected, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(sent(), ['clear 2']);
    expect(points(), hasLength(2));
    expect(graph(tester).selected, isNull);
  });

  testWidgets('follows points driven over a cable', (tester) async {
    final node = addNode();
    await pumpBody(tester, node);
    expect(graph(tester).positions, isEmpty);

    gateway.sendList(controller.instanceId, handle(), 0, '0 1');
    gateway.sendList(controller.instanceId, handle(), 0, '100 0');
    controller.refreshGuiValues();
    await tester.pump();
    expect(graph(tester).positions, [(0.0, 1.0), (1.0, 0.0)]);

    gateway.sendMessage(controller.instanceId, handle(), 0, 'clear');
    controller.refreshGuiValues();
    await tester.pump();
    expect(graph(tester).positions, isEmpty);
  });
}
