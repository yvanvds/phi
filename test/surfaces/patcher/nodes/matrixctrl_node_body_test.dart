import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_matrix_grid.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/matrixctrl_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the `.matrixctrl` grid body (issue #474): each gesture
/// reaches the fake gateway as the `set <index> <value>` the object takes, and
/// the grid follows cells driven from the graph through the per-cell poll.
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
    final registered = NodeTypeRegistry.instance.find(Obj.gMatrixctrl)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: Obj.gMatrixctrl,
        defaultSize: registered.defaultSize,
        sizeForArgs: registered.sizeForArgs,
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
  FakeNode fake() => gateway.nodes.values.single;
  List<double> cells() => [for (final c in fake().guiCells) double.parse(c)];

  List<String> listsSent() => [
    for (final c in gateway.calls)
      if (c.startsWith('sendList:${handle()}:0:'))
        c.substring('sendList:${handle()}:0:'.length),
  ];

  PatchMatrixGrid grid(WidgetTester tester) =>
      tester.widget<PatchMatrixGrid>(find.byType(PatchMatrixGrid));

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

  /// The centre of cell ([column], [row]) on screen.
  Offset cellCentre(WidgetTester tester, int column, int row) {
    final box = tester.getRect(find.byType(PatchMatrixGrid));
    final g = grid(tester);
    return box.topLeft +
        Offset(
          box.width * (column + 0.5) / g.columns,
          box.height * (row + 0.5) / g.rows,
        );
  }

  test('registers as a per-cell GUI body sized from its arguments', () {
    final d = NodeTypeRegistry.instance.find(Obj.gMatrixctrl)!;
    expect(d.readsGuiValue, isTrue);
    expect(d.guiValueRead, GuiValueRead.cells);
    expect(d.sizeForArgs!(''), const Size(112, 112));
    expect(d.sizeForArgs!('16 4').width, 224);
    expect(d.sizeForArgs!('16 4').height, 56);
    expect(d.sizeForArgs!('256 256'), const Size(384, 384), reason: 'capped');
  });

  testWidgets('renders its configured shape from the cells', (tester) async {
    final node = addNode(args: '4 3 0 4');
    gateway.sendList(controller.instanceId, handle(), 0, '1 2 2');
    await pumpBody(tester, node);

    expect(find.byType(MatrixctrlNodeBody), findsOneWidget);
    expect(grid(tester).columns, 4);
    expect(grid(tester).rows, 3);
    expect(grid(tester).values, hasLength(12));
    // Column 1, row 2 is index 5, half full.
    expect(grid(tester).values[5], 0.5);
    expect(grid(tester).values.where((v) => v != 0), hasLength(1));
  });

  testWidgets('a click toggles a cell on, and again off', (tester) async {
    final node = addNode(args: '4 4');
    await pumpBody(tester, node);
    gateway.calls.clear();

    await tester.tapAt(cellCentre(tester, 2, 1));
    await tester.pump();
    expect(listsSent(), ['set 9 1']);
    expect(cells()[9], 1);
    expect(grid(tester).values[9], 1);

    await tester.tapAt(cellCentre(tester, 2, 1));
    await tester.pump();
    expect(listsSent().last, 'set 9 0');
    expect(cells()[9], 0);
    expect(grid(tester).values[9], 0);
  });

  testWidgets('a drag paints across the cells it crosses', (tester) async {
    final node = addNode(args: '4 4');
    await pumpBody(tester, node);
    gateway.calls.clear();

    final stroke = await tester.startGesture(cellCentre(tester, 0, 2));
    for (var c = 1; c < 4; c++) {
      await stroke.moveTo(cellCentre(tester, c, 2));
      await tester.pump();
    }
    await stroke.up();
    await tester.pump();

    expect(listsSent(), ['set 2 1', 'set 6 1', 'set 10 1', 'set 14 1']);
    expect([for (var c = 0; c < 4; c++) cells()[c * 4 + 2]], [1, 1, 1, 1]);
    expect(cells().where((v) => v != 0), hasLength(4));
  });

  testWidgets('a vertical drag on a stepped grid steps the cell', (
    tester,
  ) async {
    final node = addNode(args: '4 4 0 4');
    await pumpBody(tester, node);
    gateway.calls.clear();

    final at = cellCentre(tester, 1, 3);
    final drag = await tester.startGesture(at);
    await drag.moveTo(at - const Offset(0, 13));
    await tester.pump();
    expect(cells()[7], 2, reason: 'two steps up');
    expect(grid(tester).values[7], 0.5, reason: 'shown as fill level');
    await drag.moveTo(at - const Offset(0, 100));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(cells()[7], 4, reason: 'clamped to the maximum');
    expect(listsSent().last, 'set 7 4');
    expect(cells().where((v) => v != 0), hasLength(1), reason: 'no painting');
  });

  testWidgets('follows cells driven over a cable', (tester) async {
    final node = addNode(args: '4 4');
    await pumpBody(tester, node);
    expect(grid(tester).values.every((v) => v == 0), isTrue);

    gateway.sendList(controller.instanceId, handle(), 0, '3 0 1');
    controller.refreshGuiValues();
    await tester.pump();
    expect(grid(tester).values[12], 1);

    gateway.sendMessage(controller.instanceId, handle(), 0, 'clear');
    controller.refreshGuiValues();
    await tester.pump();
    expect(grid(tester).values[12], 0);
  });
}
