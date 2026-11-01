import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_nodes_field.dart';
import 'package:phi/domain/patcher/field_node.dart';
import 'package:phi/domain/patcher/nodes_view.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/nodes_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the `.nodes` interpolation field (issue #476): the cursor
/// and the layout gestures reach the fake gateway as the messages the object
/// takes, the nodes are shaded by the weights it sends, and the field follows
/// a layout driven from the graph through the per-cell poll.
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
    final registered = NodeTypeRegistry.instance.find(Obj.gNodes)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: Obj.gNodes,
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

  int handle() =>
      gateway.nodes.entries.firstWhere((e) => e.value.type == Obj.gNodes).key;

  /// What reached the object's inlet 0, as lists.
  List<String> sent() => [
    for (final c in gateway.calls)
      if (c.startsWith('sendList:${handle()}:0:'))
        c.substring('sendList:${handle()}:0:'.length),
  ];

  PatchNodesField field(WidgetTester tester) =>
      tester.widget<PatchNodesField>(find.byType(PatchNodesField));

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

  /// The screen position of field point ([x], [y]).
  Offset fieldAt(WidgetTester tester, double x, double y) {
    final box = tester.getRect(find.byType(PatchNodesField));
    final (px, py) = NodesView(
      width: box.width,
      height: box.height,
    ).toPixel(x, y);
    return box.topLeft + Offset(px, py);
  }

  void seed(String state) =>
      gateway.restoreGuiValue(controller.instanceId, handle(), state);

  test('registers as a square per-cell GUI body with two outlets', () {
    final d = NodeTypeRegistry.instance.find(Obj.gNodes)!;
    expect(d.readsGuiValue, isTrue);
    expect(d.guiValueRead, GuiValueRead.cells);
    expect(d.defaultSize, const Size(160, 160));
    expect([for (final o in d.outputs) o.label], ['weights', 'distances']);
    expect(d.inputs, hasLength(1));
  });

  testWidgets('draws the fresh field: four unit nodes sharing the origin', (
    tester,
  ) async {
    final node = addNode();
    await pumpBody(tester, node);

    expect(find.byType(NodesNodeBody), findsOneWidget);
    expect(field(tester).nodes, List.filled(4, const FieldNode(0, 0, 1)));
    expect(field(tester).weights, [0.25, 0.25, 0.25, 0.25]);
    expect(field(tester).cursor, (0.0, 0.0));
  });

  testWidgets('a drag carries the cursor, sends it and shades by weight', (
    tester,
  ) async {
    final node = addNode(args: '2');
    await pumpBody(tester, node);
    seed('0.25 0.25 0.2 0.75 0.75 0.2');
    gateway.calls.clear();

    final drag = await tester.startGesture(fieldAt(tester, 0.5, 0.5));
    await tester.pump();
    await drag.moveTo(fieldAt(tester, 0.7, 0.75));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(sent(), ['0.5 0.5', '0.7 0.75']);
    expect(field(tester).cursor, (0.7, 0.75));
    expect(field(tester).weights, [0, 1]);
  });

  testWidgets('an alt-drag on a node moves it, keeping its radius', (
    tester,
  ) async {
    final node = addNode(args: '2');
    await pumpBody(tester, node);
    seed('0.25 0.25 0.2 0.75 0.75 0.2');
    controller.refreshGuiValues();
    await tester.pump();
    gateway.calls.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final drag = await tester.startGesture(fieldAt(tester, 0.75, 0.75));
    await tester.pump();
    expect(field(tester).selected, 1);
    await drag.moveTo(fieldAt(tester, 0.5, 0.6));
    await tester.pump();
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(sent(), ['set 1 0.5 0.6']);
    expect(gateway.nodes[handle()]!.guiCells[1], '0.5 0.6 0.2');
    expect(field(tester).nodes[1], const FieldNode(0.5, 0.6, 0.2));
    expect(field(tester).selected, isNull);
  });

  testWidgets('an alt-drag on a rim changes the radius', (tester) async {
    final node = addNode(args: '2');
    await pumpBody(tester, node);
    seed('0.25 0.25 0.2 0.75 0.75 0.2');
    controller.refreshGuiValues();
    await tester.pump();
    gateway.calls.clear();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final drag = await tester.startGesture(fieldAt(tester, 0.25, 0.45));
    await drag.moveTo(fieldAt(tester, 0.25, 0.55));
    await tester.pump();
    await drag.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(sent(), ['set 0 0.25 0.25 0.3']);
    expect(field(tester).nodes[0], const FieldNode(0.25, 0.25, 0.3));
  });

  testWidgets('follows a layout driven over a cable', (tester) async {
    final node = addNode();
    await pumpBody(tester, node);

    gateway.sendList(controller.instanceId, handle(), 0, '0.5 0.5 0.25');
    controller.refreshGuiValues();
    await tester.pump();
    expect(field(tester).nodes, const [FieldNode(0.5, 0.5, 0.25)]);

    gateway.sendList(
      controller.instanceId,
      handle(),
      0,
      'set 0 0.25 0.75 0.125',
    );
    controller.refreshGuiValues();
    await tester.pump();
    expect(field(tester).nodes, const [FieldNode(0.25, 0.75, 0.125)]);
  });
}
