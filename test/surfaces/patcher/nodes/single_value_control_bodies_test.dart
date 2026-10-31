import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/design/widgets/patcher/patch_dial_knob.dart';
import 'package:phi/design/widgets/patcher/patch_incdec_stepper.dart';
import 'package:phi/design/widgets/patcher/patch_led_lamp.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_text_button.dart';
import 'package:phi/design/widgets/patcher/patch_text_edit_box.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/engine/state/patcher_controller.dart';
import 'package:phi/surfaces/patcher/nodes/dial_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/incdec_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/label_switch_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/list_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/textedit_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_node_types.dart';
import 'package:yse/yse.dart';

import '../../../engine/test_doubles/fake_patcher_gateway.dart';

/// Widget tests for the libYSE 3.0 single-value control bodies (issue #470):
/// `.dial`, `.incdec`, `.led`, `.textbutton`, `.textedit` and `.l`. Each body's
/// gesture reaches the fake gateway through the verb the engine object takes,
/// and each follows a value driven from the graph through the GUI poll.
void main() {
  late FakePatcherGateway gateway;
  late PatcherController controller;

  setUp(() {
    registerBuiltInPatcherNodes();
    gateway = FakePatcherGateway();
    controller = PatcherController(gateway);
  });

  tearDown(() => controller.dispose());

  /// Add a node of [type] through its real registration, so the poll treats it
  /// exactly as it treats one dropped on the canvas.
  PatchNode addNode(String type, {String args = ''}) {
    final registered = NodeTypeRegistry.instance.find(type)!;
    return controller.addNode(
      desc: NodeDescriptor(
        type: type,
        defaultSize: registered.defaultSize,
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

  /// Land [value] on the object the way a cable would — Dart is told nothing.
  void driveFromEngine(String value) =>
      gateway.nodes.values.single.guiValue = value;

  Future<void> poll(WidgetTester tester) async {
    controller.refreshGuiValues();
    await tester.pump();
  }

  List<String> callsLike(String prefix) =>
      gateway.calls.where((c) => c.startsWith(prefix)).toList();

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

  group('.dial', () {
    PatchDialKnob knob(WidgetTester tester) =>
        tester.widget<PatchDialKnob>(find.byType(PatchDialKnob));

    testWidgets('an upward drag turns it up through sendFloat', (tester) async {
      final node = addNode(Obj.gDial);
      await pumpBody(tester, node);
      expect(find.byType(DialNodeBody), findsOneWidget);
      expect(knob(tester).position, 0);

      await tester.drag(find.byType(PatchDialKnob), const Offset(0, -75));
      await tester.pump();

      final sent = callsLike('sendFloat:${handle()}:0:');
      expect(sent, isNotEmpty);
      final last = double.parse(sent.last.split(':').last);
      expect(last, greaterThan(0.2));
      expect(last, lessThanOrEqualTo(0.5));
      expect(knob(tester).position, closeTo(last, 0.001));
    });

    testWidgets('the readout is the mapped value its range sends', (
      tester,
    ) async {
      final node = addNode(Obj.gDial, args: '0 127 1 1');
      driveFromEngine('0.5');
      await pumpBody(tester, node);

      expect(knob(tester).position, 0.5);
      // 63.5 rounds half away from zero, as the engine's int mode does.
      expect(find.text('64'), findsOneWidget);
    });

    testWidgets('a cable-driven position moves the knob, but not mid-drag', (
      tester,
    ) async {
      final node = addNode(Obj.gDial, args: '20 20000');
      await pumpBody(tester, node);

      driveFromEngine('0.25');
      await poll(tester);
      expect(knob(tester).position, 0.25);
      expect(find.text('5015'), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PatchDialKnob)),
      );
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump();
      final held = knob(tester).position;

      driveFromEngine('0.9');
      await poll(tester);
      expect(knob(tester).position, held, reason: 'the hand has it');

      await gesture.up();
      await tester.pump();
      expect(knob(tester).position, 0.9, reason: 'release re-reads');
    });
  });

  group('.incdec', () {
    testWidgets('the top half sends inc, the bottom half dec', (tester) async {
      final node = addNode(Obj.gIncdec, args: '1 0 10 0');
      await pumpBody(tester, node);
      expect(find.byType(IncdecNodeBody), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      final rect = tester.getRect(find.byType(PatchIncdecStepper));
      await tester.tapAt(rect.topCenter + const Offset(0, 4));
      await tester.pump();
      await tester.tapAt(rect.topCenter + const Offset(0, 4));
      await tester.pump();
      expect(callsLike('sendMessage:${handle()}:0:'), [
        'sendMessage:${handle()}:0:inc',
        'sendMessage:${handle()}:0:inc',
      ]);
      expect(find.text('2'), findsOneWidget);

      await tester.tapAt(rect.bottomCenter - const Offset(0, 4));
      await tester.pump();
      expect(callsLike('sendMessage').last, 'sendMessage:${handle()}:0:dec');
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the held half lights while pressed', (tester) async {
      final node = addNode(Obj.gIncdec);
      await pumpBody(tester, node);
      final rect = tester.getRect(find.byType(PatchIncdecStepper));

      final gesture = await tester.startGesture(
        rect.bottomCenter - const Offset(0, 4),
      );
      await tester.pump();
      expect(
        tester
            .widget<PatchIncdecStepper>(find.byType(PatchIncdecStepper))
            .pressed,
        isFalse,
      );
      await gesture.up();
      await tester.pump();
      expect(
        tester
            .widget<PatchIncdecStepper>(find.byType(PatchIncdecStepper))
            .pressed,
        isNull,
      );
    });

    testWidgets('a cable-driven count shows up', (tester) async {
      final node = addNode(Obj.gIncdec);
      await pumpBody(tester, node);

      driveFromEngine('-7');
      await poll(tester);
      expect(find.text('-7'), findsOneWidget);
    });
  });

  group('.led / .textbutton', () {
    bool lampOn(WidgetTester tester) =>
        tester.widget<PatchLedLamp>(find.byType(PatchLedLamp)).on;

    testWidgets('a latching .led shows its label and toggles by int', (
      tester,
    ) async {
      final node = addNode(Obj.gLed, args: 'mute');
      await pumpBody(tester, node);
      expect(find.text('mute'), findsOneWidget);
      expect(lampOn(tester), isFalse);

      await tester.tap(find.byType(PatchLedLamp));
      await tester.pump();
      expect(gateway.calls, contains('sendInt:${handle()}:0:1'));
      expect(lampOn(tester), isTrue);

      await tester.tap(find.byType(PatchLedLamp));
      await tester.pump();
      expect(gateway.calls, contains('sendInt:${handle()}:0:0'));
      expect(lampOn(tester), isFalse);
    });

    testWidgets('a cable-driven state lights the lamp', (tester) async {
      final node = addNode(Obj.gLed);
      await pumpBody(tester, node);

      driveFromEngine('1');
      await poll(tester);
      expect(lampOn(tester), isTrue);

      driveFromEngine('0');
      await poll(tester);
      expect(lampOn(tester), isFalse);
    });

    testWidgets('a momentary .led is lit while held, and sends one press', (
      tester,
    ) async {
      final node = addNode(Obj.gLed, args: 'momentary go now');
      await pumpBody(tester, node);
      // The keyword is not part of the label; the rest is, joined.
      expect(find.text('go now'), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PatchLedLamp)),
      );
      await tester.pump();
      expect(lampOn(tester), isTrue);
      expect(callsLike('sendInt:${handle()}:0:'), ['sendInt:${handle()}:0:1']);

      await gesture.up();
      await tester.pump();
      expect(lampOn(tester), isFalse);
      expect(callsLike('sendInt'), hasLength(1), reason: 'release is silent');
    });

    testWidgets('a momentary press reported by the engine flashes it', (
      tester,
    ) async {
      final node = addNode(Obj.gLed, args: 'momentary');
      await pumpBody(tester, node);

      driveFromEngine('1');
      await poll(tester);
      expect(lampOn(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(lampOn(tester), isFalse);
    });

    testWidgets('a .textbutton draws its label, pressed while on', (
      tester,
    ) async {
      final node = addNode(Obj.gTextbutton, args: 'filter cutoff');
      await pumpBody(tester, node);
      expect(find.byType(LabelSwitchNodeBody), findsOneWidget);
      expect(find.byType(PatchLedLamp), findsNothing);
      expect(find.text('filter cutoff'), findsOneWidget);

      bool pressed() =>
          tester.widget<PatchTextButton>(find.byType(PatchTextButton)).pressed;
      expect(pressed(), isFalse);

      await tester.tap(find.byType(PatchTextButton));
      await tester.pump();
      expect(gateway.calls, contains('sendInt:${handle()}:0:1'));
      expect(pressed(), isTrue);

      driveFromEngine('0');
      await poll(tester);
      expect(pressed(), isFalse);
    });
  });

  group('.textedit', () {
    String shown(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;

    testWidgets('Enter commits the text through restoreGuiValue', (
      tester,
    ) async {
      final node = addNode(Obj.gTextedit, args: 'hello');
      await pumpBody(tester, node);
      expect(find.byType(TexteditNodeBody), findsOneWidget);
      expect(shown(tester), 'hello');

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // A restore is a list on inlet 0 — which the engine stores and sends.
      expect(gateway.calls, contains('sendList:${handle()}:0:hello world'));
      expect(gateway.guiValue(controller.instanceId, handle()), 'hello world');
      expect(shown(tester), 'hello world');
    });

    testWidgets('Escape abandons the edit', (tester) async {
      final node = addNode(Obj.gTextedit, args: 'keep');
      await pumpBody(tester, node);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'scratch');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(shown(tester), 'keep');
      expect(callsLike('sendList'), isEmpty);
    });

    testWidgets('focus loss commits a dirty field', (tester) async {
      final node = addNode(Obj.gTextedit);
      await pumpBody(tester, node);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(
        tester.widget<PatchTextEditBox>(find.byType(PatchTextEditBox)).focused,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'typed');
      await tester.pump();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();

      expect(gateway.calls, contains('sendList:${handle()}:0:typed'));
    });

    testWidgets('cable-driven text shows up, but not under the caret', (
      tester,
    ) async {
      final node = addNode(Obj.gTextedit);
      await pumpBody(tester, node);

      driveFromEngine('from a cable');
      await poll(tester);
      expect(shown(tester), 'from a cable');

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'mine');
      driveFromEngine('again');
      await poll(tester);
      expect(shown(tester), 'mine');
    });
  });

  group('.l', () {
    testWidgets('a tap sends the stored list with a bang', (tester) async {
      final node = addNode(Obj.gList);
      driveFromEngine('1 2 three');
      await pumpBody(tester, node);
      expect(find.byType(ListNodeBody), findsOneWidget);
      expect(find.text('1 2 three'), findsOneWidget);

      await tester.tap(find.byType(PatchListBox));
      await tester.pump();
      expect(gateway.calls, contains('sendBang:${handle()}:0'));
    });

    testWidgets('a list set over a cable replaces what it shows', (
      tester,
    ) async {
      final node = addNode(Obj.gList);
      await pumpBody(tester, node);
      expect(find.text('list'), findsOneWidget, reason: 'empty placeholder');

      gateway.sendList(controller.instanceId, handle(), 0, 'a b c');
      await poll(tester);
      expect(find.text('a b c'), findsOneWidget);
    });
  });
}
