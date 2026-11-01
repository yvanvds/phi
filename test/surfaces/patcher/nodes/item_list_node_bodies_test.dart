import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_menu_box.dart';
import 'package:phi/design/widgets/patcher/patch_radio_group.dart';
import 'package:phi/design/widgets/patcher/patch_tab_strip.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/item_list_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the selection control bodies (issue #471): `.umenu`,
/// `.radiogroup` and `.tab`. A pick reaches the fake gateway as the item
/// number on inlet 0, what is lit is what the object then holds — single and
/// `multi` — a selection driven from the graph arrives through the GUI poll,
/// and the box follows the item count.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  /// Add a node of [type] through its real registration.
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
      ),
      position: Offset.zero,
    );
  }

  int handle() => gateway.nodes.keys.single;

  /// Land a selection on the object the way a cable would.
  void driveFromEngine(String list) =>
      gateway.sendList(gateway.instances.keys.single, handle(), 0, list);

  Future<void> poll(WidgetTester tester) async {
    controller.refreshGuiValues();
    await tester.pump();
  }

  List<String> sentInts() =>
      gateway.calls.where((c) => c.startsWith('sendInt:${handle()}:')).toList();

  Future<void> pumpBody(WidgetTester tester, PatchNode node) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ListenableBuilder(
              listenable: node,
              builder: (context, _) => SizedBox(
                width: node.size.width,
                height: node.size.height,
                child: NodeTypeRegistry.instance.find(node.type)!.buildBody!(
                  context,
                  node,
                  controller,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('.radiogroup', () {
    PatchRadioGroup group(WidgetTester tester) =>
        tester.widget<PatchRadioGroup>(find.byType(PatchRadioGroup));

    testWidgets('renders its items, one row each, and picks by tap', (
      tester,
    ) async {
      final node = addNode(Obj.gRadiogroup, args: 'sine square saw');
      await pumpBody(tester, node);
      expect(find.byType(ItemListNodeBody), findsOneWidget);
      expect(find.text('sine'), findsOneWidget);
      expect(find.text('saw'), findsOneWidget);
      expect(group(tester).selected, {0});
      expect(group(tester).multi, isFalse);

      await tester.tap(find.byKey(PatchRadioGroup.itemKey(2)));
      await tester.pump();
      expect(sentInts(), ['sendInt:${handle()}:0:2']);
      expect(group(tester).selected, {2});
      expect(tester.takeException(), isNull);
    });

    testWidgets('multi toggles check boxes', (tester) async {
      final node = addNode(Obj.gRadiogroup, args: 'multi 4');
      await pumpBody(tester, node);
      expect(group(tester).multi, isTrue);
      expect(group(tester).selected, isEmpty);

      await tester.tap(find.byKey(PatchRadioGroup.itemKey(1)));
      await tester.tap(find.byKey(PatchRadioGroup.itemKey(3)));
      await tester.pump();
      expect(group(tester).selected, {1, 3});

      await tester.tap(find.byKey(PatchRadioGroup.itemKey(1)));
      await tester.pump();
      expect(group(tester).selected, {3});
      expect(gateway.nodes[handle()]!.guiValue, '0 0 0 1');
    });

    testWidgets('follows a cable-driven selection', (tester) async {
      final node = addNode(Obj.gRadiogroup, args: 'a b c');
      await pumpBody(tester, node);
      driveFromEngine('c');
      await poll(tester);
      expect(group(tester).selected, {2});
    });

    testWidgets('is as tall as its item count, and a retype re-reads it', (
      tester,
    ) async {
      final node = addNode(Obj.gRadiogroup, args: 'a b');
      final two = node.size;
      await pumpBody(tester, node);

      controller.setNodeParams(node.id, 'a b c d');
      await poll(tester);
      expect(node.size.height, closeTo(two.height * 2, 0.01));
      expect(find.text('d'), findsOneWidget);
      expect(group(tester).labels, ['a', 'b', 'c', 'd']);
      expect(tester.takeException(), isNull);
    });
  });

  group('.tab', () {
    PatchTabStrip strip(WidgetTester tester) =>
        tester.widget<PatchTabStrip>(find.byType(PatchTabStrip));

    testWidgets('lays its tabs out in a row and picks by tap', (tester) async {
      final node = addNode(Obj.gTab, args: 'one two three');
      await pumpBody(tester, node);
      final one = tester.getCenter(find.byKey(PatchTabStrip.itemKey(0)));
      final three = tester.getCenter(find.byKey(PatchTabStrip.itemKey(2)));
      expect(three.dy, one.dy);
      expect(three.dx, greaterThan(one.dx));

      await tester.tap(find.byKey(PatchTabStrip.itemKey(1)));
      await tester.pump();
      expect(sentInts(), ['sendInt:${handle()}:0:1']);
      expect(strip(tester).selected, {1});
    });

    testWidgets('lights more than one tab with multi', (tester) async {
      final node = addNode(Obj.gTab, args: 'multi a b c');
      await pumpBody(tester, node);
      await tester.tap(find.byKey(PatchTabStrip.itemKey(0)));
      await tester.tap(find.byKey(PatchTabStrip.itemKey(2)));
      await tester.pump();
      expect(strip(tester).selected, {0, 2});

      driveFromEngine('0 1 0');
      await poll(tester);
      expect(strip(tester).selected, {1});
    });

    testWidgets('is as wide as its item count', (tester) async {
      final two = addNode(Obj.gTab, args: 'a b').size;
      final four = addNode(Obj.gTab, args: 'a b c d').size;
      expect(four.width, greaterThan(two.width));
      expect(four.height, two.height);
    });
  });

  group('.umenu', () {
    testWidgets('shows the selection and picks from its drop-down', (
      tester,
    ) async {
      final node = addNode(Obj.gUmenu, args: 'sine square saw');
      await pumpBody(tester, node);
      expect(find.byType(PatchMenuBox), findsOneWidget);
      expect(find.text('sine'), findsOneWidget);
      expect(find.text('saw'), findsNothing, reason: 'closed');

      await tester.tap(find.byType(PatchMenuBox));
      await tester.pumpAndSettle();
      expect(find.text('saw'), findsOneWidget);
      await tester.tap(find.text('saw'));
      await tester.pumpAndSettle();

      expect(sentInts(), ['sendInt:${handle()}:0:2']);
      expect(find.text('square'), findsNothing, reason: 'closed again');
      expect(find.text('saw'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('multi checks several items and lists them closed', (
      tester,
    ) async {
      final node = addNode(Obj.gUmenu, args: 'multi a b c');
      await pumpBody(tester, node);
      expect(find.text(PatchMenuBox.nothing), findsOneWidget);

      await tester.tap(find.byType(PatchMenuBox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('c'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(sentInts(), [
        'sendInt:${handle()}:0:0',
        'sendInt:${handle()}:0:2',
      ]);

      await tester.tapAt(Offset.zero); // dismiss
      await tester.pumpAndSettle();
      expect(find.text('a, c'), findsOneWidget);
    });

    testWidgets('follows a cable-driven selection', (tester) async {
      final node = addNode(Obj.gUmenu, args: 'sine square saw');
      await pumpBody(tester, node);
      driveFromEngine('1');
      await poll(tester);
      expect(find.text('square'), findsOneWidget);
    });

    testWidgets('a longer item name makes a wider menu', (tester) async {
      final short = addNode(Obj.gUmenu, args: 'a b').size;
      final long = addNode(Obj.gUmenu, args: 'a filtered-noise').size;
      expect(long.width, greaterThan(short.width));
      expect(long.height, short.height);
    });
  });
}
