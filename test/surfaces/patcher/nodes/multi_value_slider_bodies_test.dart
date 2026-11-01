import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_range_bar.dart';
import 'package:phi/design/widgets/patcher/patch_slider_bank.dart';
import 'package:phi/design/widgets/patcher/patch_xy_pad.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/multislider_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/range_slider_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/xy_slider_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the libYSE 3.0 multi-value slider bodies (issue #472):
/// `.rslider`, `.xyslider` and `.multislider`. Each gesture reaches the fake
/// gateway as the message the engine object takes, and each body follows
/// cells driven from the graph through the per-cell GUI poll.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  PatchNode addNode(String type, {String args = ''}) {
    final registered = NodeTypeRegistry.instance.find(type)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: type,
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

  Future<void> poll(WidgetTester tester) async {
    controller.refreshGuiValues();
    await tester.pump();
  }

  List<String> listsSent() => [
    for (final c in gateway.calls)
      if (c.startsWith('sendList:${handle()}:0:'))
        c.substring('sendList:${handle()}:0:'.length),
  ];

  List<double> numbersOf(String list) => [
    for (final t in list.split(' ')) double.parse(t),
  ];

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

  test('all three register as per-cell GUI bodies', () {
    for (final type in [Obj.gRslider, Obj.gXyslider, Obj.gMultislider]) {
      final d = NodeTypeRegistry.instance.find(type)!;
      expect(d.readsGuiValue, isTrue, reason: type);
      expect(d.guiValueRead, GuiValueRead.cells, reason: type);
    }
  });

  group('.rslider', () {
    PatchRangeBar bar(WidgetTester tester) =>
        tester.widget<PatchRangeBar>(find.byType(PatchRangeBar));

    testWidgets('draws its two ends as positions inside its bounds', (
      tester,
    ) async {
      final node = addNode(Obj.gRslider, args: '0 100');
      gateway.sendList(controller.instanceId, handle(), 0, '25 75');
      await pumpBody(tester, node);

      expect(find.byType(RangeSliderNodeBody), findsOneWidget);
      expect(bar(tester).low, 0.25);
      expect(bar(tester).high, 0.75);
    });

    testWidgets('dragging an end sends both ends as one list', (tester) async {
      final node = addNode(Obj.gRslider, args: '0 100');
      gateway.sendList(controller.instanceId, handle(), 0, '25 75');
      await pumpBody(tester, node);
      gateway.calls.clear();

      // Take the top end (a quarter of the way down) and lift it.
      final box = tester.getRect(find.byType(PatchRangeBar));
      final gesture = await tester.startGesture(
        box.topCenter + Offset(0, box.height * 0.25),
      );
      await gesture.moveBy(Offset(0, -box.height * 0.15));
      await gesture.up();
      await tester.pump();

      final last = numbersOf(listsSent().last);
      expect(last[0], 25, reason: 'the low end stayed');
      expect(last[1], closeTo(90, 0.5));
      expect(bar(tester).high, closeTo(0.9, 0.005));
      expect(fake().guiCells.map(double.parse).last, closeTo(90, 0.5));
    });

    testWidgets('dragging the middle slides the whole range', (tester) async {
      final node = addNode(Obj.gRslider, args: '0 100');
      gateway.sendList(controller.instanceId, handle(), 0, '25 75');
      await pumpBody(tester, node);
      gateway.calls.clear();

      final box = tester.getRect(find.byType(PatchRangeBar));
      final gesture = await tester.startGesture(box.center);
      await gesture.moveBy(Offset(0, box.height * 0.1));
      await gesture.up();
      await tester.pump();

      final last = numbersOf(listsSent().last);
      expect(last[0], closeTo(15, 0.5));
      expect(last[1], closeTo(65, 0.5));
    });

    testWidgets('follows cable-driven ends, but not mid-drag', (tester) async {
      final node = addNode(Obj.gRslider);
      await pumpBody(tester, node);

      fake().guiCells = ['0', '127'];
      await poll(tester);
      expect(bar(tester).low, 0);
      expect(bar(tester).high, 1);

      final box = tester.getRect(find.byType(PatchRangeBar));
      final gesture = await tester.startGesture(
        box.topCenter + const Offset(0, 1),
      );
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      final held = bar(tester).high;

      fake().guiCells = ['0', '10'];
      await poll(tester);
      expect(bar(tester).high, held, reason: 'the pointer owns it');

      await gesture.up();
      await tester.pump();
      expect(bar(tester).high, closeTo(10 / 127, 1e-6), reason: 're-read');
    });
  });

  group('.xyslider', () {
    PatchXyPad pad(WidgetTester tester) =>
        tester.widget<PatchXyPad>(find.byType(PatchXyPad));

    testWidgets('a press sends x and y together, y rising upwards', (
      tester,
    ) async {
      final node = addNode(Obj.gXyslider, args: '0 1 -1 1');
      await pumpBody(tester, node);
      expect(find.byType(XySliderNodeBody), findsOneWidget);

      final box = tester.getRect(find.byType(PatchXyPad));
      await tester.tapAt(
        box.topLeft + Offset(box.width * 0.25, box.height * 0.25),
      );
      await tester.pump();

      final sent = numbersOf(listsSent().single);
      expect(sent[0], closeTo(0.25, 0.01));
      expect(sent[1], closeTo(0.5, 0.02));
      expect(pad(tester).x, closeTo(0.25, 0.01));
      expect(pad(tester).y, closeTo(0.75, 0.01));
    });

    testWidgets('a drag moves the puck through every point', (tester) async {
      final node = addNode(Obj.gXyslider);
      await pumpBody(tester, node);

      await tester.drag(find.byType(PatchXyPad), const Offset(40, -40));
      await tester.pump();

      expect(listsSent().length, greaterThan(1));
      final last = numbersOf(listsSent().last);
      expect(last[0], greaterThan(63.5));
      expect(last[1], greaterThan(63.5));
    });

    testWidgets('follows a cable-driven position', (tester) async {
      final node = addNode(Obj.gXyslider, args: '0 10 0 10');
      await pumpBody(tester, node);

      gateway.sendList(controller.instanceId, handle(), 0, '2.5 7.5');
      await poll(tester);
      expect(pad(tester).x, 0.25);
      expect(pad(tester).y, 0.75);
    });
  });

  group('.multislider', () {
    PatchSliderBank bank(WidgetTester tester) =>
        tester.widget<PatchSliderBank>(find.byType(PatchSliderBank));

    testWidgets('draws one bar per cell, and its box follows its size', (
      tester,
    ) async {
      final small = addNode(Obj.gMultislider, args: '4');
      await pumpBody(tester, small);
      expect(find.byType(MultisliderNodeBody), findsOneWidget);
      expect(bank(tester).values, [0, 0, 0, 0]);

      final wide = addNode(Obj.gMultislider, args: '16');
      expect(wide.size.width, greaterThan(small.size.width));
    });

    testWidgets('dragging across writes each crossed cell with set', (
      tester,
    ) async {
      final node = addNode(Obj.gMultislider, args: '4 0 100');
      await pumpBody(tester, node);
      gateway.calls.clear();

      final box = tester.getRect(find.byType(PatchSliderBank));
      final gesture = await tester.startGesture(
        box.topLeft + Offset(box.width * 0.125, box.height * 0.5),
      );
      await gesture.moveTo(
        box.topLeft + Offset(box.width * 0.875, box.height * 0.5),
      );
      await gesture.up();
      await tester.pump();

      final written = {
        for (final l in listsSent())
          if (l.startsWith('set ')) int.parse(l.split(' ')[1]),
      };
      expect(written, {0, 1, 2, 3});
      for (final cell in fake().guiCells) {
        expect(double.parse(cell), closeTo(50, 1));
      }
      for (final v in bank(tester).values) {
        expect(v, closeTo(0.5, 0.01));
      }
    });

    testWidgets('a list of another length re-lays the bars', (tester) async {
      final node = addNode(Obj.gMultislider, args: '4');
      await pumpBody(tester, node);

      gateway.sendList(controller.instanceId, handle(), 0, '0 127 63.5');
      await poll(tester);
      expect(bank(tester).values, [0, 1, 0.5]);
    });

    testWidgets('ignores inbound cells mid-stroke and re-reads on release', (
      tester,
    ) async {
      final node = addNode(Obj.gMultislider, args: '2');
      await pumpBody(tester, node);

      final box = tester.getRect(find.byType(PatchSliderBank));
      final gesture = await tester.startGesture(
        box.topLeft + Offset(box.width * 0.25, 1),
      );
      await tester.pump();
      expect(bank(tester).values.first, closeTo(1, 0.02));

      fake().guiCells = ['0', '0', '0'];
      await poll(tester);
      expect(bank(tester).values, hasLength(2), reason: 'the pointer owns it');

      await gesture.up();
      await tester.pump();
      expect(bank(tester).values, [0, 0, 0]);
    });
  });
}
