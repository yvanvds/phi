import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_keyboard.dart';
import 'package:phi/design/widgets/patcher/patch_staff.dart';
import 'package:phi/domain/patcher/keyboard_layout.dart';
import 'package:phi/domain/patcher/patch_gui_property.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/staff_note.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/kslider_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/nslider_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the libYSE 3.0 keyboard and staff bodies (issue #473):
/// `.kslider` and `.nslider`. Each gesture reaches the fake gateway as the
/// message the engine object takes, and each body follows notes driven from
/// the graph through the per-cell GUI poll.
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

  test('both register as per-cell GUI bodies', () {
    for (final type in [Obj.gKslider, Obj.gNslider]) {
      final d = NodeTypeRegistry.instance.find(type)!;
      expect(d.readsGuiValue, isTrue, reason: type);
      expect(d.guiValueRead, GuiValueRead.cells, reason: type);
      expect(d.inputs, isNotEmpty, reason: type);
      expect(d.outputs, hasLength(2), reason: type);
    }
  });

  group('.kslider', () {
    PatchKeyboard keyboard(WidgetTester tester) =>
        tester.widget<PatchKeyboard>(find.byType(PatchKeyboard));

    /// The centre-x of [pitch]'s key, at fraction [y] down the keyboard.
    Offset keyPoint(WidgetTester tester, int pitch, double y) {
      final box = tester.getRect(find.byType(PatchKeyboard));
      final b = keyboard(tester).layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * y);
    }

    testWidgets('shows the default range and lights cable-driven keys', (
      tester,
    ) async {
      final node = addNode(Obj.gKslider);
      await pumpBody(tester, node);
      expect(find.byType(KsliderNodeBody), findsOneWidget);
      expect(keyboard(tester).layout.low, KeyboardLayout.defaultLow);
      expect(keyboard(tester).layout.high, KeyboardLayout.defaultHigh);
      expect(keyboard(tester).held, isEmpty);

      gateway.sendList(controller.instanceId, handle(), 0, '60 90');
      gateway.sendList(controller.instanceId, handle(), 0, '64 40');
      await poll(tester);
      expect(keyboard(tester).held, {60: 90, 64: 40});

      gateway.sendList(controller.instanceId, handle(), 0, '60 0');
      await poll(tester);
      expect(keyboard(tester).held, {64: 40});
    });

    testWidgets('reads only the keys it shows', (tester) async {
      final node = addNode(Obj.gKslider);
      controller.setGuiPropertyPrimitive(
        node.id,
        PatchGuiProperty.keyLow,
        '60',
      );
      controller.setGuiPropertyPrimitive(
        node.id,
        PatchGuiProperty.keyHigh,
        '72',
      );
      await pumpBody(tester, node);
      expect(keyboard(tester).layout.low, 60);
      expect(keyboard(tester).layout.high, 72);

      gateway.sendInt(controller.instanceId, handle(), 0, 20);
      gateway.sendInt(controller.instanceId, handle(), 0, 62);
      await poll(tester);
      final cells = controller.guiValueCellsOf(node.id);
      expect(cells[62], '100');
      expect(cells[20], isNot('100'), reason: 'outside the window: unread');
      expect(keyboard(tester).held, {62: 100});
    });

    testWidgets('a press plays the key, louder lower down, and the lift '
        'releases it', (tester) async {
      final node = addNode(Obj.gKslider);
      await pumpBody(tester, node);
      gateway.calls.clear();

      final press = await tester.startGesture(keyPoint(tester, 62, 0.9));
      await tester.pump();
      final on = listsSent().single.split(' ');
      expect(on.sublist(0, 2), ['set', '62']);
      final loud = int.parse(on[2]);
      expect(loud, greaterThan(100));
      expect(fake().guiCells[62], '$loud');
      expect(keyboard(tester).held, {62: loud});

      await press.up();
      await tester.pump();
      expect(listsSent().last, 'set 62 0');
      expect(keyboard(tester).held, isEmpty);

      gateway.calls.clear();
      await tester.tapAt(keyPoint(tester, 62, 0.2));
      await tester.pump();
      final soft = int.parse(listsSent().first.split(' ')[2]);
      expect(soft, lessThan(loud));
      expect(listsSent().last, 'set 62 0', reason: 'a tap releases too');
    });

    testWidgets('a black key wins at the top of the keyboard', (tester) async {
      final node = addNode(Obj.gKslider);
      await pumpBody(tester, node);
      gateway.calls.clear();
      await tester.tapAt(keyPoint(tester, 61, 0.3));
      await tester.pump();
      expect(listsSent().first, startsWith('set 61 '));
    });

    testWidgets('sliding across keys releases each before the next', (
      tester,
    ) async {
      final node = addNode(Obj.gKslider);
      await pumpBody(tester, node);
      gateway.calls.clear();

      final press = await tester.startGesture(keyPoint(tester, 60, 0.9));
      await press.moveTo(keyPoint(tester, 62, 0.9));
      await press.moveTo(keyPoint(tester, 64, 0.9));
      await tester.pump();
      final sent = [for (final l in listsSent()) l.split(' ').sublist(1)];
      expect([for (final s in sent) s[0]], ['60', '60', '62', '62', '64']);
      expect(sent[1][1], '0');
      expect(sent[3][1], '0');
      expect(keyboard(tester).held.keys, [64]);
      await press.up();
      await tester.pump();
      expect(listsSent().last, 'set 64 0');
    });

    testWidgets('a fixed velocity plays every press the same', (tester) async {
      final node = addNode(Obj.gKslider);
      controller.setGuiPropertyPrimitive(
        node.id,
        PatchGuiProperty.keyVelocity,
        '77',
      );
      await pumpBody(tester, node);
      gateway.calls.clear();
      await tester.tapAt(keyPoint(tester, 60, 0.95));
      await tester.tapAt(keyPoint(tester, 65, 0.1));
      await tester.pump();
      expect(listsSent(), ['set 60 77', 'set 60 0', 'set 65 77', 'set 65 0']);
    });
  });

  group('.nslider', () {
    StaffNote note(WidgetTester tester) =>
        tester.widget<PatchStaff>(find.byType(PatchStaff)).note;

    List<int> intsSent() => [
      for (final c in gateway.calls)
        if (c.startsWith('sendInt:${handle()}:0:'))
          int.parse(c.split(':').last),
    ];

    testWidgets('draws the note the object holds, and follows the graph', (
      tester,
    ) async {
      final node = addNode(Obj.gNslider, args: '36 96 -1');
      await pumpBody(tester, node);
      expect(find.byType(NsliderNodeBody), findsOneWidget);
      expect(note(tester), StaffNote.of(36, 0));

      gateway.sendInt(controller.instanceId, handle(), 0, 61);
      await poll(tester);
      expect(note(tester), StaffNote.of(61, -1), reason: 'D flat');

      gateway.sendList(controller.instanceId, handle(), 0, '61 1');
      await poll(tester);
      expect(note(tester), StaffNote.of(61, 1), reason: 'C sharp');
    });

    testWidgets('dragging up raises the pitch, inside its bounds', (
      tester,
    ) async {
      final node = addNode(Obj.gNslider, args: '55 65');
      gateway.sendInt(controller.instanceId, handle(), 0, 60);
      await pumpBody(tester, node);
      gateway.calls.clear();

      final box = tester.getRect(find.byType(PatchStaff));
      final drag = await tester.startGesture(box.center);
      for (var i = 0; i < 6; i++) {
        await drag.moveBy(const Offset(0, -4));
        await tester.pump();
      }
      final sent = intsSent();
      expect(sent, isNotEmpty);
      for (var i = 1; i < sent.length; i++) {
        expect(sent[i], greaterThan(sent[i - 1]), reason: 'rising');
      }
      expect(fake().guiCells.first, '${sent.last}');

      // Far past the top: held at the maximum.
      await drag.moveBy(const Offset(0, -400));
      await tester.pump();
      expect(intsSent().last, 65);
      await drag.up();
      await tester.pump();
      expect(note(tester), StaffNote.of(65, 0));
    });

    testWidgets('ignores the graph mid-drag, and re-reads on release', (
      tester,
    ) async {
      final node = addNode(Obj.gNslider);
      gateway.sendInt(controller.instanceId, handle(), 0, 60);
      await pumpBody(tester, node);

      final box = tester.getRect(find.byType(PatchStaff));
      final drag = await tester.startGesture(box.center);
      await drag.moveBy(const Offset(0, -30));
      await tester.pump();
      final held = note(tester);

      gateway.sendInt(controller.instanceId, handle(), 0, 40);
      await poll(tester);
      expect(note(tester), held, reason: 'the pointer owns it');

      await drag.up();
      await tester.pump();
      expect(note(tester), StaffNote.of(40, 0));
    });
  });
}
