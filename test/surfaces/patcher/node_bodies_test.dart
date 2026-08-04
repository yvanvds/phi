import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/button_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/message_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/sine_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/slider_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/toggle_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the live GUI node bodies (issue #223): each control's
/// interaction reaches the fake gateway (`sendFloat` / `sendBang`), and a
/// number body's display refreshes from the value the gateway reports back
/// through `guiValue`.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  NodeDescriptor desc(String type, {String args = ''}) => NodeDescriptor(
    type: type,
    title: type,
    defaultSize: const Size(120, 80),
    defaultArgs: args,
    inputs: const [],
    outputs: const [],
    buildBody: (ctx, node, controller) => const SizedBox.shrink(),
  );

  PatchNode addNode(String type, {String args = ''}) => controller.addNode(
    desc: desc(type, args: args),
    position: Offset.zero,
  );

  /// The single created object's native handle — its key in the gateway.
  int handle() => gateway.nodes.keys.single;

  Future<void> pumpBody(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: 120, height: 180, child: body)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('slider body pushes a sendFloat through the gateway', (
    tester,
  ) async {
    final node = addNode(Obj.gSlider);
    await pumpBody(tester, SliderNodeBody(node: node, controller: controller));

    tester.widget<PhiFader>(find.byType(PhiFader)).onChanged(0.4);
    await tester.pump();

    expect(gateway.calls, contains('sendFloat:${handle()}:0:0.400'));
  });

  testWidgets('toggle body sends 1 on, 0 off', (tester) async {
    final node = addNode(Obj.gToggle);
    await pumpBody(tester, ToggleNodeBody(node: node, controller: controller));

    await tester.tap(find.byType(PhiToggle));
    await tester.pump();
    expect(gateway.calls, contains('sendFloat:${handle()}:0:1.000'));

    await tester.tap(find.byType(PhiToggle));
    await tester.pump();
    expect(gateway.calls, contains('sendFloat:${handle()}:0:0.000'));
  });

  testWidgets('button body bangs the hot inlet on tap', (tester) async {
    final node = addNode(Obj.gButton);
    await pumpBody(tester, ButtonNodeBody(node: node, controller: controller));

    await tester.tap(find.byType(ButtonNodeBody));
    await tester.pump();

    expect(gateway.calls, contains('sendBang:${handle()}:0'));
  });

  testWidgets('message body fires a bang on tap and shows its message', (
    tester,
  ) async {
    final node = addNode(Obj.gMessage, args: 'hello');
    await pumpBody(tester, MessageNodeBody(node: node, controller: controller));

    expect(find.text('hello'), findsOneWidget);

    await tester.tap(find.byType(MessageNodeBody));
    await tester.pump();

    expect(gateway.calls, contains('sendBang:${handle()}:0'));
  });

  testWidgets('number body (.f) sends the value and displays the refreshed '
      'guiValue', (tester) async {
    final node = addNode(Obj.gFloat);
    await pumpBody(tester, NumberNodeBody(node: node, controller: controller));

    await tester.enterText(find.byType(TextField), '2.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // The value reached the gateway...
    expect(gateway.calls, contains('sendFloat:${handle()}:0:2.500'));
    // ...and the field now shows the value the gateway reports back (guiValue),
    // not a Dart-side echo.
    expect(gateway.guiValue(controller.instanceId, handle()), '2.5');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '2.5',
    );
  });

  testWidgets('number body (.i) rounds to a whole number', (tester) async {
    final node = addNode(Obj.gInt);
    await pumpBody(
      tester,
      NumberNodeBody(node: node, controller: controller, integer: true),
    );

    await tester.enterText(find.byType(TextField), '3.7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(gateway.calls, contains('sendFloat:${handle()}:0:4.000'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '4',
    );
  });

  testWidgets('number body seeds its display from the object guiValue', (
    tester,
  ) async {
    final node = addNode(Obj.gFloat);
    // Simulate a value already set on the native object (e.g. from a cable).
    gateway.nodes.values.single.guiValue = '7';
    await pumpBody(tester, NumberNodeBody(node: node, controller: controller));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '7',
    );
  });

  // ─── editing behaviour (issue #353) ─────────────────────────────────────

  testWidgets('number body selects its whole value when it takes focus, so '
      'typing replaces it', (tester) async {
    final node = addNode(Obj.gFloat);
    gateway.nodes.values.single.guiValue = '12';
    await pumpBody(tester, NumberNodeBody(node: node, controller: controller));

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump();

    final controllerOfField = tester.widget<TextField>(field).controller!;
    expect(controllerOfField.selection.textInside('12'), '12');
  });

  testWidgets('number body commits what was typed when it loses focus', (
    tester,
  ) async {
    final node = addNode(Obj.gFloat);
    await pumpBody(tester, NumberNodeBody(node: node, controller: controller));

    await tester.enterText(find.byType(TextField), '3.5');
    await tester.pump();
    // No Enter — just walk away, the way clicking elsewhere on the canvas does.
    tester.widget<TextField>(find.byType(TextField)).focusNode!.unfocus();
    await tester.pump();

    expect(gateway.calls, contains('sendFloat:${handle()}:0:3.500'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '3.5',
    );
  });

  testWidgets('number body losing focus untouched pushes nothing', (
    tester,
  ) async {
    final node = addNode(Obj.gFloat);
    gateway.nodes.values.single.guiValue = '9';
    await pumpBody(tester, NumberNodeBody(node: node, controller: controller));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.widget<TextField>(find.byType(TextField)).focusNode!.unfocus();
    await tester.pump();

    // Clicking through a number box must never re-send its own value.
    expect(gateway.calls.where((c) => c.startsWith('sendFloat')), isEmpty);
  });

  testWidgets('Escape throws the edit away and restores the live guiValue', (
    tester,
  ) async {
    final node = addNode(Obj.gFloat);
    gateway.nodes.values.single.guiValue = '5';
    await pumpBody(tester, NumberNodeBody(node: node, controller: controller));

    await tester.enterText(find.byType(TextField), '999');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(gateway.calls.where((c) => c.startsWith('sendFloat')), isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '5',
    );
  });

  // ─── the ~sine readout (issue #354) ─────────────────────────────────────
  // The body used to print a hardcoded '440' whatever the object was set to.

  testWidgets('sine body shows the node creation frequency, not a hardcoded '
      '440', (tester) async {
    final node = addNode(Obj.dSine, args: '660');
    await pumpBody(tester, SineNodeBody(node: node, controller: controller));

    expect(find.text('660'), findsOneWidget);
    expect(find.text('440'), findsNothing);
  });

  testWidgets('sine body prefers the engine live guiValue over its args', (
    tester,
  ) async {
    final node = addNode(Obj.dSine, args: '440');
    // What a cable into the freq inlet leaves behind on the native object.
    gateway.nodes.values.single.guiValue = '523.25';
    await pumpBody(tester, SineNodeBody(node: node, controller: controller));

    expect(find.text('523.25'), findsOneWidget);
    expect(find.text('440'), findsNothing);
  });

  testWidgets('sine body shows a placeholder when no frequency is known', (
    tester,
  ) async {
    final node = addNode(Obj.dSine);
    await pumpBody(tester, SineNodeBody(node: node, controller: controller));

    // A dash, not an invented number.
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('the rendered sine node follows a params apply and its undo', (
    tester,
  ) async {
    // Through the real composition: PatcherNodeView listens to the node, and
    // setNodeParams (apply, undo and redo alike) wakes it.
    registerBuiltInPatcherNodes();
    final node = addNode(Obj.dSine, args: '440');
    await pumpBody(tester, PatcherNodeView(node: node, controller: controller));

    Finder readout(String value) => find.descendant(
      of: find.byType(SineNodeBody),
      matching: find.text(value),
    );

    expect(readout('440'), findsOneWidget);

    controller.applyParams(node.id, '660');
    await tester.pump();
    expect(readout('660'), findsOneWidget);
    expect(readout('440'), findsNothing);

    controller.undo();
    await tester.pump();
    expect(readout('440'), findsOneWidget);

    controller.redo();
    await tester.pump();
    expect(readout('660'), findsOneWidget);
  });
}
