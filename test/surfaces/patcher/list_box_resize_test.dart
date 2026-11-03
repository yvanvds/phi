import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/domain/patcher/patch_gui_property.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// A `.l` list box has a stored width (issue #533): a right-edge resize sets
/// it as one journaled step, a reload keeps it, and a patch saved before list
/// boxes could be resized still opens them at the default width. A list longer
/// than the box is cut off and shows in full in a tooltip.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  PatchNode addList() {
    final d = NodeTypeRegistry.instance.find(Obj.gList)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: d.type,
        defaultSize: d.defaultSize,
        sizeForGui: d.sizeForGui,
        defaultArgs: '',
        inputs: d.inputs,
        outputs: d.outputs,
        buildBody: d.buildBody,
        readsGuiValue: d.readsGuiValue,
      ),
      position: Offset.zero,
    );
  }

  void resizeTo(PatchNode node, double width) => controller
    ..beginWidthResize(node.id)
    ..previewWidth(width)
    ..endWidthResize();

  PatcherController reload() {
    final dump = gateway.dumpJson(controller.instanceId);
    final other = gateway.createInstance();
    gateway.parseJson(other, dump);
    final reloaded = PatcherController.bound(gateway, instanceId: other)
      ..rebuildFromInstance();
    addTearDown(reloaded.dispose);
    return reloaded;
  }

  group('controller', () {
    test('a list box is width-resizable, a message box is not', () {
      expect(PatcherController.isWidthResizable(Obj.gList), isTrue);
      expect(PatcherController.isWidthResizable(Obj.gText), isTrue);
      expect(PatcherController.isWidthResizable(Obj.gMessage), isFalse);
    });

    test('a fresh list box opens at the default width with no stored w', () {
      final node = addList();
      expect(node.size.width, PatchListBox.defaultWidth);
      expect(controller.listBoxWidthOf(node.id), isNull);
    });

    test('a resize widens it as one undoable step', () {
      final node = addList();
      final height = node.size.height;
      controller
        ..beginWidthResize(node.id)
        ..previewWidth(200)
        ..previewWidth(260.4)
        ..endWidthResize();
      expect(node.size, Size(260, height));
      expect(controller.listBoxWidthOf(node.id), 260);
      expect(
        gateway.nodes.values.single.gui[PatchGuiProperty.width],
        '260',
        reason: 'written to the engine object, so it saves',
      );

      controller.undo();
      expect(node.size.width, PatchListBox.defaultWidth);
      expect(controller.listBoxWidthOf(node.id), isNull);
      expect(controller.undoScope.canUndo, isFalse);
      controller.redo();
      expect(node.size.width, 260);
    });

    test('a resize is held to the list box range', () {
      final node = addList();
      resizeTo(node, 5);
      expect(node.size.width, PatchListBox.minWidth);
      resizeTo(node, 5000);
      expect(node.size.width, PatchListBox.maxWidth);
    });

    test('a cancelled resize puts the width back', () {
      final node = addList();
      resizeTo(node, 300);
      controller
        ..beginWidthResize(node.id)
        ..previewWidth(500)
        ..abortWidthResize();
      expect(node.size.width, 300);
      expect(controller.listBoxWidthOf(node.id), 300);
    });

    test('the width survives save → reload', () {
      final node = addList();
      resizeTo(node, 320);
      final back = reload();
      final copy = back.graph.nodes.single;
      expect(back.listBoxWidthOf(copy.id), 320);
      expect(copy.size, node.size);
    });

    test('a list box saved without a width reloads at the default width', () {
      addList();
      final dump = gateway.dumpJson(controller.instanceId);
      expect(dump, isNot(contains('"w"')), reason: 'nothing stored');
      final back = reload();
      expect(back.graph.nodes.single.size.width, PatchListBox.defaultWidth);
    });

    test('the width rides along a duplicate', () {
      final node = addList();
      resizeTo(node, 240);
      controller.selectNode(node.id);
      controller.duplicateSelection();
      final copy = controller.graph.selectedNodes.single;
      expect(controller.listBoxWidthOf(copy), 240);
      expect(controller.graph.nodeById(copy)!.size.width, 240);
    });
  });

  group('body', () {
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
                  child: Builder(
                    builder: (context) => NodeTypeRegistry.instance
                        .find(node.type)!
                        .buildBody!(context, node, controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    const long = 'note 60 100 ctl 61 100';

    RenderParagraph paragraph(WidgetTester tester) =>
        tester.renderObject<RenderParagraph>(find.text(long));

    testWidgets('a list longer than the box is cut off, with a tooltip', (
      tester,
    ) async {
      final node = addList();
      gateway.nodes.values.single.guiValue = long;
      await pumpBody(tester, node);
      expect(paragraph(tester).didExceedMaxLines, isTrue);
      expect(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == long),
        findsOneWidget,
      );
    });

    testWidgets('a widened box shows the whole list and no tooltip', (
      tester,
    ) async {
      final node = addList();
      gateway.nodes.values.single.guiValue = long;
      resizeTo(node, PatchListBox.maxWidth);
      await pumpBody(tester, node);
      expect(paragraph(tester).didExceedMaxLines, isFalse);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('a short list has no tooltip', (tester) async {
      final node = addList();
      gateway.nodes.values.single.guiValue = '1 2';
      await pumpBody(tester, node);
      expect(find.text('1 2'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
