import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_note_metrics.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/design/widgets/patcher/patch_object_box_metrics.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';
import 'package:phi/domain/patcher/patch_gui_property.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// The annotation object on the canvas is a **note** (issue #436): its free
/// text — every word of it — on a sticky-note field, with no object name
/// printed and no port dots, sized to the content it shows. Driven through
/// [PatcherNodeView] + [PatcherController] because the binding is the point:
/// the type decides the chrome, and the box is measured from the very line
/// the note renders.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  /// The catalogue entry the engine documents for `.text`: one free-text
  /// `text` parameter, no ports.
  const textDesc = PatchObjectDescriptor(
    type: Obj.gText,
    description: 'text label',
    category: PatchObjectCategory.gui,
    isDsp: false,
    inlets: [],
    outlets: [],
    params: [
      PatchParamDescriptor(
        name: 'text',
        doc: 'label text',
        defaultValue: '',
        range: 'any string',
      ),
    ],
  );

  setUp(() {
    NodeTypeRegistry.instance.clear();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() {
    controller.dispose();
    NodeTypeRegistry.instance.clear();
  });

  Future<void> pumpNode(WidgetTester tester, PatchNode node) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ListenableBuilder(
              listenable: node,
              builder: (context, _) => SizedBox(
                width: node.size.width,
                height: node.size.height,
                child: PatcherNodeView(node: node, controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a note renders its whole content and only its content', (
    tester,
  ) async {
    final node = controller.addObject(
      desc: textDesc,
      position: Offset.zero,
      args: 'warm pad from here',
    );
    await pumpNode(tester, node);

    expect(find.byType(PatchNoteBox), findsOneWidget);
    expect(find.byType(PatchObjectBox), findsNothing);
    // The content whole — the bug half of issue #436 — and no `text` name
    // printed in front of it: a comment, not a device.
    expect(find.text('warm pad from here'), findsOneWidget);
    expect(find.text('text warm pad from here'), findsNothing);
  });

  testWidgets('a note has no port dots', (tester) async {
    final node = controller.addObject(
      desc: textDesc,
      position: Offset.zero,
      args: 'no ports here',
    );
    await pumpNode(tester, node);

    expect(find.byType(PatchPortDot), findsNothing);
  });

  testWidgets('the note is sized to the content it renders', (tester) async {
    final node = controller.addObject(
      desc: textDesc,
      position: Offset.zero,
      args: 'warm pad from here',
    );

    // Measured from the display line — the content alone, not
    // `text warm pad from here` — or the box would be wider than what it
    // draws by exactly one never-rendered word.
    expect(
      node.size,
      PatchObjectBoxMetrics.sizeFor(
        text: 'warm pad from here',
        inputs: 0,
        outputs: 0,
      ),
    );
    await pumpNode(tester, node);
    expect(tester.getSize(find.byType(PatchNoteBox)), node.size);
  });

  testWidgets('an empty note shows the placeholder at the placeholder size', (
    tester,
  ) async {
    final node = controller.addObject(desc: textDesc, position: Offset.zero);
    await pumpNode(tester, node);

    expect(find.text(PatchNoteBox.placeholder), findsOneWidget);
    expect(
      node.size,
      PatchObjectBoxMetrics.sizeFor(
        text: PatchNoteBox.placeholder,
        inputs: 0,
        outputs: 0,
      ),
    );
  });

  testWidgets('the note follows a params apply and its undo', (tester) async {
    final node = controller.addObject(
      desc: textDesc,
      position: Offset.zero,
      args: 'first words',
    );
    await pumpNode(tester, node);
    final initial = node.size;

    controller.applyParams(node.id, 'a much longer annotation than before');
    await tester.pump();
    expect(find.text('a much longer annotation than before'), findsOneWidget);
    expect(find.text('first words'), findsNothing);
    expect(node.size.width, greaterThan(initial.width));

    controller.undo();
    await tester.pump();
    expect(find.text('first words'), findsOneWidget);
    expect(node.size, initial);
  });

  group('multi-line, resizable notes (issue #488)', () {
    const paragraph =
        'A sine runs into the dac. Drag the slider to sweep its frequency '
        'and listen to how the pitch follows; then try a saw instead.';

    PatchNode note([String args = paragraph]) =>
        controller.addObject(desc: textDesc, position: Offset.zero, args: args);

    void resizeTo(PatchNode node, double width) {
      controller
        ..beginNoteResize(node.id)
        ..previewNoteWidth(width)
        ..endNoteResize();
    }

    testWidgets('a paragraph wraps at the default width and grows down', (
      tester,
    ) async {
      final node = note();
      expect(node.size.width, PatchNoteMetrics.defaultWidth);
      expect(node.size, PatchNoteMetrics.sizeFor(display: paragraph));
      expect(
        node.size.height,
        greaterThan(
          PatchObjectBoxMetrics.sizeFor(
            text: 'x',
            inputs: 0,
            outputs: 0,
          ).height,
        ),
      );
      await pumpNode(tester, node);
      expect(tester.getSize(find.byType(PatchNoteBox)), node.size);
      expect(find.text(paragraph), findsOneWidget);
    });

    testWidgets('line breaks are kept, on screen and in the args', (
      tester,
    ) async {
      final node = note('# Title\nfirst line');
      expect(controller.argsOf(node.id), '# Title\nfirst line');
      await pumpNode(tester, node);
      // The heading marker is dropped; the break is not.
      expect(find.text('Title\nfirst line'), findsOneWidget);
    });

    test(
      'a resize sets the width, re-wraps, persists and undoes in one step',
      () {
        final node = note();
        final initial = node.size;

        controller.beginNoteResize(node.id);
        controller.previewNoteWidth(300);
        controller.previewNoteWidth(400.4);
        controller.endNoteResize();

        expect(node.size.width, 400);
        expect(node.size.height, lessThan(initial.height));
        expect(controller.noteWidthOf(node.id), 400);
        // Written to the engine's GUI properties, which is what the dump saves.
        final native =
            gateway.instances[controller.instanceId]!.nodes.values.single;
        expect(native.gui[PatchGuiProperty.width], '400');

        controller.undo();
        expect(node.size, initial);
        expect(controller.noteWidthOf(node.id), isNull);
        expect(native.gui.containsKey(PatchGuiProperty.width), isFalse);

        controller.redo();
        expect(node.size.width, 400);
        expect(native.gui[PatchGuiProperty.width], '400');
      },
    );

    test('a resize that ends where it started journals nothing', () {
      final node = note();
      resizeTo(node, 300);
      controller.beginNoteResize(node.id);
      controller.previewNoteWidth(420);
      controller.previewNoteWidth(300);
      controller.endNoteResize();
      expect(controller.noteWidthOf(node.id), 300);

      // One undo is the first resize itself — the round trip added no step.
      controller.undo();
      expect(controller.noteWidthOf(node.id), isNull);
      expect(controller.undoScope.canUndo, isFalse);
    });

    test('a cancelled resize puts the width back', () {
      final node = note();
      resizeTo(node, 300);
      controller.beginNoteResize(node.id);
      controller.previewNoteWidth(500);
      controller.abortNoteResize();
      expect(node.size.width, 300);
      expect(controller.noteWidthOf(node.id), 300);
    });

    test('the width rides along a delete-undo, a duplicate and a paste', () {
      final node = note();
      resizeTo(node, 320);

      controller.selectNode(node.id);
      controller.deleteSelection();
      controller.undo();
      expect(controller.noteWidthOf(node.id), 320);
      expect(controller.graph.nodeById(node.id)!.size.width, 320);

      controller.selectNode(node.id);
      controller.duplicateSelection();
      final copy = controller.graph.selectedNodes.single;
      expect(copy, isNot(node.id));
      expect(controller.noteWidthOf(copy), 320);

      controller.selectNode(node.id);
      controller.copySelection();
      controller.pasteClipboard();
      final pasted = controller.graph.selectedNodes.single;
      expect(controller.noteWidthOf(pasted), 320);
      // Each copy wrote it onto its own native object, so it saves too.
      for (final n in gateway.instances[controller.instanceId]!.nodes.values) {
        expect(n.gui[PatchGuiProperty.width], '320');
      }
    });

    test('width and breaks survive save → reload', () {
      final node = note('# Title\n$paragraph');
      resizeTo(node, 360);
      final saved = node.size;

      final dump = gateway.dumpJson(controller.instanceId);
      final other = gateway.createInstance();
      gateway.parseJson(other, dump);
      final reloaded = PatcherController.bound(gateway, instanceId: other)
        ..rebuildFromInstance();
      addTearDown(reloaded.dispose);

      final back = reloaded.graph.nodes.single;
      expect(reloaded.argsOf(back.id), '# Title\n$paragraph');
      expect(reloaded.noteWidthOf(back.id), 360);
      expect(back.size, saved);
    });

    test('an edit to the text re-wraps at the width it was given', () {
      final node = note('short');
      resizeTo(node, 200);
      expect(node.size.width, 200);

      controller.applyParams(node.id, paragraph);
      expect(node.size.width, 200, reason: 'a resized note keeps its width');
      expect(
        node.size,
        PatchNoteMetrics.sizeFor(display: paragraph, width: 200),
      );
    });

    test('only a note can be resized', () {
      final sine = controller.addObject(
        desc: FakePatcherGateway.defaultCatalogue.firstWhere(
          (d) => d.type == Obj.dSine,
        ),
        position: Offset.zero,
      );
      final before = sine.size;
      controller
        ..beginNoteResize(sine.id)
        ..previewNoteWidth(500)
        ..endNoteResize();
      expect(sine.size, before);
      expect(controller.guiPropertyOf(sine.id, PatchGuiProperty.width), '');
    });
  });
}
