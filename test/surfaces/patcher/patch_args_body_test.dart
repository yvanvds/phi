import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/patch_args_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// The default node body (issue #356): a node with no hand-authored GUI body
/// prints its type and creation arguments the way a Max object box does, and
/// keeps printing the truth as the params dialog edits them.
///
/// Driven through [PatcherNodeView] rather than the body alone, because the
/// refresh is the point: the body caches nothing, but it only *rebuilds*
/// because the view listens to the node that `setNodeParams` wakes.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  NodeDescriptor desc(String type, {String args = ''}) => NodeDescriptor(
    type: type,
    title: type,
    defaultSize: const Size(140, 70),
    defaultArgs: args,
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => const Text('hand-authored'),
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
            child: SizedBox(
              width: node.size.width,
              height: node.size.height,
              child: PatcherNodeView(node: node, controller: controller),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an unregistered type prints its type and creation arguments', (
    tester,
  ) async {
    final node = controller.addNode(
      desc: desc('.metro', args: '250'),
      position: Offset.zero,
    );
    await pumpNode(tester, node);

    expect(find.byType(PatchArgsBody), findsOneWidget);
    expect(find.text('.metro 250'), findsOneWidget);
  });

  testWidgets('a type with no arguments prints just its type', (tester) async {
    final node = controller.addNode(
      desc: desc('.print'),
      position: Offset.zero,
    );
    await pumpNode(tester, node);

    // Not `.print ` with a dangling space, and not an empty box either.
    expect(find.text('.print'), findsOneWidget);
  });

  testWidgets('the body follows a params apply and its undo/redo', (
    tester,
  ) async {
    final node = controller.addNode(
      desc: desc('.metro', args: '250'),
      position: Offset.zero,
    );
    await pumpNode(tester, node);
    expect(find.text('.metro 250'), findsOneWidget);

    // The whole point of issue #356: applying the dialog changed what the
    // object does, and the canvas used to keep showing nothing at all.
    controller.applyParams(node.id, '500');
    await tester.pump();
    expect(find.text('.metro 500'), findsOneWidget);
    expect(find.text('.metro 250'), findsNothing);

    controller.undo();
    await tester.pump();
    expect(find.text('.metro 250'), findsOneWidget);

    controller.redo();
    await tester.pump();
    expect(find.text('.metro 500'), findsOneWidget);
  });

  testWidgets('a hand-authored body still wins over the default', (
    tester,
  ) async {
    // `~sine` renders its own freq readout; the fallback must not displace it.
    final registered = desc(Obj.dSine, args: '440');
    NodeTypeRegistry.instance.register(registered);
    final node = controller.addNode(desc: registered, position: Offset.zero);
    await pumpNode(tester, node);

    expect(find.text('hand-authored'), findsOneWidget);
    expect(find.byType(PatchArgsBody), findsNothing);
  });
}
