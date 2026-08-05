import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/tokens/phi_colors.dart';
import 'package:phi/design/widgets/patcher/patch_gui_object.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/design/widgets/patcher/patch_object_box_metrics.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// An engine object on the canvas is an **object box** (issue #379): one
/// bordered line reading `sine 440`, sized to that line, with no header
/// saying the same thing again above it — and, since issue #380, no `~`/`.`
/// prefix drawn either: the line's colour carries that.
///
/// Driven through [PatcherNodeView] rather than the box alone, because the
/// binding is the point: which chrome a node gets is the descriptor's decision,
/// the line is read from the controller on every build and never cached, and it
/// only *rebuilds* because the view listens to the node that `setNodeParams`
/// wakes.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  /// A descriptor for a hand-authored **GUI** body — the other kind of node,
  /// the one that is its own bare control (issue #381).
  NodeDescriptor guiDesc(String type, {String args = ''}) => NodeDescriptor(
    type: type,
    defaultSize: const Size(140, 70),
    defaultArgs: args,
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => const Text('hand-authored'),
  );

  /// A descriptor for a plain engine object: no body and no tuned size.
  NodeDescriptor boxDesc(String type, {String args = ''}) => NodeDescriptor(
    type: type,
    defaultArgs: args,
    inputs: const [],
    outputs: const [],
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

  testWidgets('an unregistered type is a box printing its name and args', (
    tester,
  ) async {
    final node = controller.addNode(
      desc: boxDesc('.metro', args: '250'),
      position: Offset.zero,
    );
    await pumpNode(tester, node);

    expect(find.byType(PatchObjectBox), findsOneWidget);
    expect(find.byType(PatchGuiObject), findsNothing);
    // Bare (issue #380) — the node's type is still the canonical `.metro`.
    expect(find.text('metro 250'), findsOneWidget);
    expect(find.text('.metro 250'), findsNothing);
    expect(node.type, '.metro');
  });

  testWidgets('a type with no arguments prints just its name', (tester) async {
    final node = controller.addNode(
      desc: boxDesc('.print'),
      position: Offset.zero,
    );
    await pumpNode(tester, node);

    // Not `print ` with a dangling space, and not an empty box either.
    expect(find.text('print'), findsOneWidget);
  });

  testWidgets('the box prints its line and nothing else', (tester) async {
    // Where a header used to print a display title over it — `OUT · L/R` above
    // a body — there is now one `Text` on the whole node, and it says `dac`.
    final node = controller.addNode(
      desc: boxDesc(Obj.dDac),
      position: Offset.zero,
    );
    await pumpNode(tester, node);

    expect(find.text('dac'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('the DSP/control domain is the line colour (issue #380)', (
    tester,
  ) async {
    Color lineColor(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(PatchObjectBox),
            matching: find.byType(Text),
          ),
        )
        .style!
        .color!;

    final dsp = controller.addNode(
      desc: boxDesc(Obj.dSine, args: '440'),
      position: Offset.zero,
    );
    await pumpNode(tester, dsp);
    expect(find.text('sine 440'), findsOneWidget);
    expect(lineColor(tester), PhiColors.cool);

    final control = controller.addNode(
      desc: boxDesc(Obj.gMetro, args: '250'),
      position: Offset.zero,
    );
    await pumpNode(tester, control);
    expect(lineColor(tester), PhiColors.fg1);
  });

  testWidgets('the box is created at the size its line needs', (tester) async {
    final node = controller.addNode(
      desc: boxDesc('.metro', args: '250'),
      position: Offset.zero,
    );

    expect(
      node.size,
      // Measured from the line it actually prints — the bare one (issue #380),
      // or the box would be sized for a character it never draws.
      PatchObjectBoxMetrics.sizeFor(
        text: 'metro 250',
        inputs: node.inputs.length,
        outputs: node.outputs.length,
      ),
    );
    await pumpNode(tester, node);
    expect(tester.getSize(find.byType(PatchObjectBox)), node.size);
  });

  testWidgets('the box follows a params apply and its undo/redo', (
    tester,
  ) async {
    final node = controller.addNode(
      desc: boxDesc('.metro', args: '250'),
      position: Offset.zero,
    );
    await pumpNode(tester, node);
    expect(find.text('metro 250'), findsOneWidget);
    final initial = node.size;

    // The whole point of issue #356: applying the edit changed what the object
    // does, and the canvas used to keep showing nothing at all.
    controller.applyParams(node.id, '5000000');
    await tester.pump();
    expect(find.text('metro 5000000'), findsOneWidget);
    expect(find.text('metro 250'), findsNothing);
    // ...and issue #379's half: a longer line gets a longer box.
    expect(node.size.width, greaterThan(initial.width));
    expect(node.size.height, initial.height);

    controller.undo();
    await tester.pump();
    expect(find.text('metro 250'), findsOneWidget);
    expect(node.size, initial);

    controller.redo();
    await tester.pump();
    expect(find.text('metro 5000000'), findsOneWidget);
  });

  testWidgets('a hand-authored GUI body is the bare control, no box', (
    tester,
  ) async {
    final registered = guiDesc(Obj.gSlider);
    NodeTypeRegistry.instance.register(registered);
    final node = controller.addNode(desc: registered, position: Offset.zero);
    await pumpNode(tester, node);

    expect(find.text('hand-authored'), findsOneWidget);
    expect(find.byType(PatchGuiObject), findsOneWidget);
    expect(find.byType(PatchObjectBox), findsNothing);
    // ...and keeps the tuned size its descriptor declares.
    expect(node.size, const Size(140, 70));
    // The control fills that rectangle edge to edge — no frame, no header band
    // and no body padding taking a bite out of it (issue #381).
    expect(tester.getSize(find.text('hand-authored')), const Size(140, 70));
  });
}
