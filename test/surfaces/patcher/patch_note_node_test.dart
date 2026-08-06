import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_note_box.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/design/widgets/patcher/patch_object_box_metrics.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';
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
}
