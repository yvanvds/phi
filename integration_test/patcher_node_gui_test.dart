import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_dial_knob.dart';
import 'package:phi/design/widgets/patcher/patch_incdec_stepper.dart';
import 'package:phi/design/widgets/patcher/patch_keyboard.dart';
import 'package:phi/design/widgets/patcher/patch_led_lamp.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_menu_box.dart';
import 'package:phi/design/widgets/patcher/patch_radio_group.dart';
import 'package:phi/design/widgets/patcher/patch_range_bar.dart';
import 'package:phi/design/widgets/patcher/patch_slider_bank.dart';
import 'package:phi/design/widgets/patcher/patch_staff.dart';
import 'package:phi/design/widgets/patcher/patch_tab_strip.dart';
import 'package:phi/design/widgets/patcher/patch_text_button.dart';
import 'package:phi/design/widgets/patcher/patch_text_edit_box.dart';
import 'package:phi/design/widgets/patcher/patch_xy_pad.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/domain/patcher/staff_note.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/nodes/list_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the live GUI bodies + argument editing (issue #223,
/// retargeted by #382) through the real [PhiApp] — real rail navigation,
/// layout, and fonts — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched.
///
/// Two user-visible flows: operating the seeded slider body writes through the
/// gateway (`sendFloat`), and double-clicking the non-GUI `~sine` node opens its
/// object box for typing, whose Enter round-trips through `setParams` into the
/// live patcher.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('operate a slider body and edit sine params via double-click', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface, which seeds slider → sine → dac.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // 1) Operate the seeded slider (a live GUI body) — its value reaches the
    //    gateway as a sendFloat.
    tester.widget<PhiFader>(find.byType(PhiFader)).onChanged(0.3);
    await tester.pump();
    expect(
      patcherGateway.calls.where((c) => c.startsWith('sendFloat')),
      isNotEmpty,
    );

    // 2) Double-click the `~sine` object box — one line reading `sine 440`
    //    since issues #379/#380, and the only thing left to aim at — to edit it
    //    in place (issue #382). Detected from raw pointer timing, so two quick
    //    taps suffice.
    final sineLine = find.text('sine 440');
    expect(sineLine, findsOneWidget);
    final at = tester.getCenter(sineLine);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    // The box seeds itself from the line the object was already printing.
    final field = find.byKey(PatchInlineObjectBox.fieldKey);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'sine 440');

    // Retype and commit → the change round-trips through setParams into the
    // patch, with no dialog anywhere in the gesture.
    await tester.enterText(field, 'sine 660');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final sine = engine.patcher.graph.nodes.firstWhere(
      (n) => n.type == Obj.dSine,
    );
    expect(engine.patcher.argsOf(sine.id), '660');
    expect(
      patcherGateway.calls.where((c) => c.startsWith('setParams')),
      isNotEmpty,
    );

    session.dispose();
    await engine.dispose();
  });

  testWidgets('the libYSE 3.0 single-value controls render and operate in run '
      'mode (issue #470)', (tester) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final patcher = engine.patcher;

    /// Add [type] with [args] through its real registration — sized exactly as
    /// one dropped from the palette.
    PatchNode gui(String type, Offset position, {String args = ''}) {
      final d = NodeTypeRegistry.instance.find(type)!;
      return patcher.addNode(
        desc: NodeDescriptor(
          type: d.type,
          defaultSize: d.defaultSize,
          defaultArgs: args,
          inputs: d.inputs,
          outputs: d.outputs,
          buildBody: d.buildBody,
          readsGuiValue: d.readsGuiValue,
          guiValueRead: d.guiValueRead,
        ),
        position: position,
      );
    }

    final dial = gui(Obj.gDial, const Offset(30, 30), args: '0 127 1 1');
    final led = gui(Obj.gLed, const Offset(110, 30), args: 'mute');
    gui(Obj.gIncdec, const Offset(230, 30));
    gui(Obj.gTextbutton, const Offset(30, 120), args: 'go');
    gui(Obj.gTextedit, const Offset(150, 120), args: 'hello');
    gui(Obj.gList, const Offset(300, 120));
    await tester.pumpAndSettle();

    // ─── all six render as their controls, in the real font ────────────────
    expect(find.byType(PatchDialKnob), findsOneWidget);
    expect(find.byType(PatchLedLamp), findsOneWidget);
    expect(find.byType(PatchIncdecStepper), findsOneWidget);
    expect(find.byType(PatchTextButton), findsOneWidget);
    expect(find.byType(PatchTextEditBox), findsOneWidget);
    expect(find.byType(PatchListBox), findsOneWidget);
    expect(find.text('mute'), findsOneWidget);
    expect(find.text('go'), findsOneWidget);
    // The dial's readout is the mapped value: 0 at position 0 of 0–127.
    expect(
      find.descendant(of: find.byType(PatchDialKnob), matching: find.text('0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    List<String> callsLike(String prefix) =>
        patcherGateway.calls.where((c) => c.startsWith(prefix)).toList();
    int handleOf(String type) => patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == type)
        .key;
    double knob() =>
        tester.widget<PatchDialKnob>(find.byType(PatchDialKnob)).position;
    bool lamp() => tester.widget<PatchLedLamp>(find.byType(PatchLedLamp)).on;

    // ─── edit mode: the controls are grab handles, not live ────────────────
    // `warnIfMissed: false`: in edit mode the body sits under an IgnorePointer
    // on purpose (issue #378), so the press lands on the canvas, not on it.
    patcherGateway.calls.clear();
    final before = dial.position;
    await tester.drag(
      find.byType(PatchDialKnob),
      const Offset(0, 32),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(dial.position, isNot(before), reason: 'the drag moved the node');
    expect(callsLike('sendFloat'), isEmpty);
    await tester.tap(find.byType(PatchLedLamp), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(callsLike('sendInt'), isEmpty);
    expect(lamp(), isFalse);

    // ─── run mode: operate the dial and the led ────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    patcherGateway.calls.clear();
    await tester.drag(find.byType(PatchDialKnob), const Offset(0, -90));
    await tester.pumpAndSettle();
    final sent = callsLike('sendFloat:${handleOf(Obj.gDial)}:0:');
    expect(sent, isNotEmpty);
    final position = double.parse(sent.last.split(':').last);
    expect(position, greaterThan(0));
    expect(knob(), closeTo(position, 0.001));
    // The readout under the knob says what the dial now sends.
    expect(
      find.descendant(
        of: find.byType(PatchDialKnob),
        matching: find.text('${(position * 127).round()}'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(PatchLedLamp));
    await tester.pumpAndSettle();
    expect(callsLike('sendInt:${handleOf(Obj.gLed)}:0:'), [
      'sendInt:${handleOf(Obj.gLed)}:0:1',
    ]);
    expect(lamp(), isTrue);

    // ─── values driven from the graph reach both through the poll ──────────
    patcherGateway.nodes[handleOf(Obj.gDial)]!.guiValue = '1';
    patcherGateway.nodes[handleOf(Obj.gLed)]!.guiValue = '0';
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(knob(), 1);
    expect(
      find.descendant(
        of: find.byType(PatchDialKnob),
        matching: find.text('127'),
      ),
      findsOneWidget,
    );
    expect(lamp(), isFalse);
    expect(led.type, Obj.gLed);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('a momentary .textbutton flashes when a press arrives over a '
      'cable in run mode (issue #514)', (tester) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final patcher = engine.patcher;
    final d = NodeTypeRegistry.instance.find(Obj.gTextbutton)!;
    final button = patcher.addNode(
      desc: NodeDescriptor(
        type: d.type,
        defaultSize: d.defaultSize,
        defaultArgs: 'momentary go',
        inputs: d.inputs,
        outputs: d.outputs,
        buildBody: d.buildBody,
        readsGuiValue: d.readsGuiValue,
        guiValueRead: d.guiValueRead,
      ),
      position: const Offset(60, 60),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    bool pressed() =>
        tester.widget<PatchTextButton>(find.byType(PatchTextButton)).pressed;
    expect(find.text('go'), findsOneWidget);
    expect(pressed(), isFalse);

    // A press lands on the native object the way a cable delivers one — the
    // canvas is told nothing, and the engine reports it to exactly one read.
    patcherGateway.sendInt(patcher.instanceId, button.id.value, 0, 1);

    // The live poller picks it up; watch frame by frame, since the flash is
    // brief by design.
    var flashed = false;
    for (var i = 0; i < 50 && !flashed; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      flashed = pressed();
    }
    expect(flashed, isTrue, reason: 'the inbound press lit the button');

    // ...and only for a moment: the press was consumed, so it goes dark.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(pressed(), isFalse);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('the selection controls render from their items, pick in run '
      'mode, and drive a connected .i (issue #471)', (tester) async {
    final patcherGateway = FakePatcherGateway()
      // The engine's `.i`: one inlet, one outlet — so it can be wired.
      ..topologyOverrides[Obj.gInt] = const PatcherNodeSnapshot(
        inputs: 1,
        outputs: 1,
        inputKinds: [PatchPortKind.control],
        outputKinds: [PatchPortKind.control],
      );
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // An empty canvas: the demo seed would sit over the controls under test.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    PatchNode gui(String type, Offset position, {String args = ''}) {
      final d = NodeTypeRegistry.instance.find(type)!;
      return patcher.addNode(
        desc: NodeDescriptor(
          type: d.type,
          defaultSize: d.defaultSize,
          sizeForArgs: d.sizeForArgs,
          defaultArgs: args,
          inputs: d.inputs,
          outputs: d.outputs,
          buildBody: d.buildBody,
          readsGuiValue: d.readsGuiValue,
          guiValueRead: d.guiValueRead,
        ),
        position: position,
      );
    }

    final radio = gui(
      Obj.gRadiogroup,
      const Offset(30, 30),
      args: 'sine square saw',
    );
    final tabs = gui(Obj.gTab, const Offset(220, 30), args: 'multi a b c');
    final menu = gui(
      Obj.gUmenu,
      const Offset(30, 170),
      args: 'sine square saw',
    );
    final number = gui(Obj.gInt, const Offset(30, 260));
    patcher.connect(
      PatchPortId(nodeId: menu.id, side: PatchPortSide.output, index: 0),
      PatchPortId(nodeId: number.id, side: PatchPortSide.input, index: 0),
    );
    await tester.pumpAndSettle();

    // ─── all three render their items, in the real font ────────────────────
    expect(find.byType(PatchRadioGroup), findsOneWidget);
    expect(find.byType(PatchTabStrip), findsOneWidget);
    expect(find.byType(PatchMenuBox), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PatchRadioGroup),
        matching: find.text('square'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(PatchTabStrip), matching: find.text('c')),
      findsOneWidget,
    );
    expect(radio.size.height, greaterThan(menu.size.height * 2.5));
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    Set<int> radioLit() =>
        tester.widget<PatchRadioGroup>(find.byType(PatchRadioGroup)).selected;
    Set<int> tabsLit() =>
        tester.widget<PatchTabStrip>(find.byType(PatchTabStrip)).selected;
    String numberShows() => tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(NumberNodeBody),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    // ─── edit mode: inert ─────────────────────────────────────────────────
    patcherGateway.calls.clear();
    await tester.tap(
      find.byKey(PatchRadioGroup.itemKey(2)),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(patcherGateway.calls.where((c) => c.startsWith('sendInt')), isEmpty);
    expect(radioLit(), {0});

    // ─── run mode: pick in each ───────────────────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    await tester.tap(find.byKey(PatchRadioGroup.itemKey(2)));
    await tester.pumpAndSettle();
    expect(radioLit(), {2});

    await tester.tap(find.byKey(PatchTabStrip.itemKey(0)));
    await tester.tap(find.byKey(PatchTabStrip.itemKey(2)));
    await tester.pumpAndSettle();
    expect(tabsLit(), {0, 2}, reason: 'multi lights more than one');

    // The drop-down: open it, pick `saw`, and outlet 0 lands on the `.i`.
    await tester.tap(find.byType(PatchMenuBox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('saw').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PatchMenuBox),
        matching: find.text('saw'),
      ),
      findsOneWidget,
    );
    expect(numberShows(), '2', reason: 'outlet 0 through the cable');

    // ─── a selection driven from the graph reaches the body ────────────────
    patcherGateway.sendList(
      patcher.instanceId,
      patcherGateway.nodes.entries
          .firstWhere((e) => e.value.type == Obj.gRadiogroup)
          .key,
      0,
      'square',
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(radioLit(), {1});

    // ─── a retype re-reads the items and re-measures the box ───────────────
    final before = tabs.size.width;
    patcher.applyParams(tabs.id, 'multi a b c d e');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(tabs.size.width, greaterThan(before));
    expect(
      find.descendant(of: find.byType(PatchTabStrip), matching: find.text('e')),
      findsOneWidget,
    );
    expect(tabsLit(), isEmpty, reason: 'new items start clear');
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('the multi-value sliders render, draw in run mode, and send '
      'their bank down a cable (issue #472)', (tester) async {
    final patcherGateway = FakePatcherGateway()
      // The engine's `.l`: one inlet, one outlet — so it can be wired.
      ..topologyOverrides[Obj.gList] = const PatcherNodeSnapshot(
        inputs: 1,
        outputs: 1,
        inputKinds: [PatchPortKind.control],
        outputKinds: [PatchPortKind.control],
      );
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // An empty canvas: the demo seed would sit over the controls under test.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    PatchNode gui(String type, Offset position, {String args = ''}) {
      final d = NodeTypeRegistry.instance.find(type)!;
      return patcher.addNode(
        desc: NodeDescriptor(
          type: d.type,
          defaultSize: d.defaultSize,
          sizeForArgs: d.sizeForArgs,
          defaultArgs: args,
          inputs: d.inputs,
          outputs: d.outputs,
          buildBody: d.buildBody,
          readsGuiValue: d.readsGuiValue,
          guiValueRead: d.guiValueRead,
        ),
        position: position,
      );
    }

    final bankNode = gui(
      Obj.gMultislider,
      const Offset(30, 30),
      args: '4 0 100',
    );
    gui(Obj.gRslider, const Offset(200, 30), args: '0 100');
    gui(Obj.gXyslider, const Offset(320, 30), args: '0 100 0 100');
    final list = gui(Obj.gList, const Offset(30, 220));
    patcher.connect(
      PatchPortId(nodeId: bankNode.id, side: PatchPortSide.output, index: 0),
      PatchPortId(nodeId: list.id, side: PatchPortSide.input, index: 0),
    );
    await tester.pumpAndSettle();

    // ─── all three render as their controls ───────────────────────────────
    expect(find.byType(PatchSliderBank), findsOneWidget);
    expect(find.byType(PatchRangeBar), findsOneWidget);
    expect(find.byType(PatchXyPad), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    List<double> bars() =>
        tester.widget<PatchSliderBank>(find.byType(PatchSliderBank)).values;
    int handleOf(String type) => patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == type)
        .key;
    List<String> listsTo(String type) => [
      for (final c in patcherGateway.calls)
        if (c.startsWith('sendList:${handleOf(type)}:0:'))
          c.substring('sendList:${handleOf(type)}:0:'.length),
    ];
    String listShows() => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(ListNodeBody),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(bars(), [0, 0, 0, 0]);

    // ─── edit mode: dragging the bank moves the node, writes nothing ───────
    patcherGateway.calls.clear();
    final before = bankNode.position;
    await tester.drag(
      find.byType(PatchSliderBank),
      const Offset(0, 32),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(bankNode.position, isNot(before), reason: 'the drag moved the node');
    expect(listsTo(Obj.gMultislider), isEmpty);
    expect(bars(), [0, 0, 0, 0]);

    // ─── run mode ─────────────────────────────────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    // Draw a rising line across the bank, left to right.
    patcherGateway.calls.clear();
    final box = tester.getRect(find.byType(PatchSliderBank));
    final stroke = await tester.startGesture(
      box.topLeft + Offset(box.width * 0.125, box.height * 0.9),
    );
    for (var i = 1; i <= 6; i++) {
      await stroke.moveTo(
        box.topLeft +
            Offset(
              box.width * (0.125 + 0.125 * i),
              box.height * (0.9 - 0.13 * i),
            ),
      );
      await tester.pump();
    }
    await stroke.up();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    final written = {
      for (final l in listsTo(Obj.gMultislider))
        if (l.startsWith('set ')) int.parse(l.split(' ')[1]),
    };
    expect(written, {0, 1, 2, 3}, reason: 'every crossed cell was drawn');
    final drawn = bars();
    expect(drawn, hasLength(4));
    for (var i = 1; i < drawn.length; i++) {
      expect(drawn[i], greaterThan(drawn[i - 1]), reason: 'a rising line');
    }

    // Outlet 0 carried the whole bank down the cable into the `.l`.
    final bank = patcherGateway.nodes[handleOf(Obj.gMultislider)]!.guiValue;
    expect(patcherGateway.nodes[handleOf(Obj.gList)]!.guiValue, bank);
    expect(listShows(), bank);
    final sentBank = [for (final t in bank.split(' ')) double.parse(t)];
    for (var i = 0; i < 4; i++) {
      expect(sentBank[i] / 100, closeTo(drawn[i], 0.001));
    }

    // The range bar and the pad answer a drag and a press too — pressed clear
    // of the port dots on their edges, which keep their cable gesture.
    patcherGateway.calls.clear();
    final bar = tester.getRect(find.byType(PatchRangeBar));
    await tester.dragFrom(
      bar.bottomCenter - const Offset(0, 40),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
    final range = listsTo(Obj.gRslider);
    expect(range, isNotEmpty);
    expect(double.parse(range.last.split(' ').last), greaterThan(0));
    final pad = tester.getRect(find.byType(PatchXyPad));
    await tester.tapAt(
      pad.topLeft + Offset(pad.width * 0.95, pad.height * 0.2),
    );
    await tester.pumpAndSettle();
    final xy = [
      for (final t in listsTo(Obj.gXyslider).single.split(' ')) double.parse(t),
    ];
    expect(xy[0], closeTo(95, 1));
    expect(xy[1], closeTo(80, 1), reason: 'y rises upwards');

    // ─── a bank-size change from a list re-lays the bars ───────────────────
    patcherGateway.sendList(
      patcher.instanceId,
      handleOf(Obj.gMultislider),
      0,
      '10 20 30 40 50 60',
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(bars(), hasLength(6));
    expect(bars().first, closeTo(0.1, 1e-9));
    expect(listShows(), '10 20 30 40 50 60');
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('a .kslider key pressed in run mode sends pitch and velocity '
      'into two .i, and a .nslider drags its note (issue #473)', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway()
      // The engine's `.i`: one inlet, one outlet — so it can be wired.
      ..topologyOverrides[Obj.gInt] = const PatcherNodeSnapshot(
        inputs: 1,
        outputs: 1,
        inputKinds: [PatchPortKind.control],
        outputKinds: [PatchPortKind.control],
      );
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // An empty canvas: the demo seed would sit over the controls under test.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    PatchNode gui(String type, Offset position, {String args = ''}) {
      final d = NodeTypeRegistry.instance.find(type)!;
      return patcher.addNode(
        desc: NodeDescriptor(
          type: d.type,
          defaultSize: d.defaultSize,
          sizeForArgs: d.sizeForArgs,
          defaultArgs: args,
          inputs: d.inputs,
          outputs: d.outputs,
          buildBody: d.buildBody,
          readsGuiValue: d.readsGuiValue,
          guiValueRead: d.guiValueRead,
        ),
        position: position,
      );
    }

    void wire(PatchNode from, int outlet, PatchNode to) => patcher.connect(
      PatchPortId(nodeId: from.id, side: PatchPortSide.output, index: outlet),
      PatchPortId(nodeId: to.id, side: PatchPortSide.input, index: 0),
    );

    final keys = gui(Obj.gKslider, const Offset(30, 30));
    final pitch = gui(Obj.gInt, const Offset(30, 160));
    final velocity = gui(Obj.gInt, const Offset(160, 160));
    final staff = gui(Obj.gNslider, const Offset(360, 30), args: '36 96');
    final staffPitch = gui(Obj.gInt, const Offset(360, 220));
    wire(keys, 0, pitch);
    wire(keys, 1, velocity);
    wire(staff, 0, staffPitch);
    await tester.pumpAndSettle();

    // ─── both render as their controls ────────────────────────────────────
    expect(find.byType(PatchKeyboard), findsOneWidget);
    expect(find.byType(PatchStaff), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    // The controller keys each node by its native handle.
    int handleOf(PatchNode node) => node.id.value;
    String shows(PatchNode number) => tester
        .widget<TextField>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is NumberNodeBody && identical(w.node, number),
            ),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    PatchKeyboard keyboard() =>
        tester.widget<PatchKeyboard>(find.byType(PatchKeyboard));
    StaffNote staffNote() =>
        tester.widget<PatchStaff>(find.byType(PatchStaff)).note;

    /// The centre of [pitch]'s key, at fraction [y] down the keyboard.
    Offset keyAt(int pitch, double y) {
      final box = tester.getRect(find.byType(PatchKeyboard));
      final b = keyboard().layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * y);
    }

    // ─── edit mode: pressing a key plays nothing ──────────────────────────
    patcherGateway.calls.clear();
    await tester.tapAt(keyAt(62, 0.5));
    await tester.pumpAndSettle();
    expect(
      patcherGateway.calls.where((c) => c.startsWith('sendList')),
      isEmpty,
    );

    // ─── run mode ─────────────────────────────────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    // Hold D4 low on the key: a loud note-on reaches both `.i`.
    final press = await tester.startGesture(keyAt(62, 0.85));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    final held = keyboard().held;
    expect(held.keys, [62]);
    expect(held[62], greaterThan(100), reason: 'lower down is louder');
    expect(patcherGateway.nodes[handleOf(pitch)]!.guiValue, '62');
    expect(patcherGateway.nodes[handleOf(velocity)]!.guiValue, '${held[62]}');
    expect(shows(pitch), '62');
    expect(shows(velocity), '${held[62]}');

    // Lift: velocity 0, the release, follows the note down the cable.
    await press.up();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(keyboard().held, isEmpty);
    expect(shows(velocity), '0');
    expect(shows(pitch), '62');

    // ─── a note sent in down a cable lights its key ───────────────────────
    patcherGateway.sendList(patcher.instanceId, handleOf(keys), 0, '67 50');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(keyboard().held, {67: 50});
    expect(shows(pitch), '67');

    // ─── the staff: drag the note up, into a connected `.i` ───────────────
    patcherGateway.sendInt(patcher.instanceId, handleOf(staff), 0, 60);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(staffNote(), StaffNote.of(60, 0));
    expect(shows(staffPitch), '60');

    final box = tester.getRect(find.byType(PatchStaff));
    final drag = await tester.startGesture(box.center);
    for (var i = 0; i < 5; i++) {
      await drag.moveBy(const Offset(0, -6));
      await tester.pump();
    }
    await drag.up();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    final raised = int.parse(shows(staffPitch));
    expect(raised, greaterThan(60));
    expect(patcherGateway.nodes[handleOf(staff)]!.guiCells.first, '$raised');
    expect(staffNote().step, greaterThan(StaffNote.middleC));

    // A note sent in shows with its spelling.
    patcherGateway.sendList(patcher.instanceId, handleOf(staff), 0, '70 -1');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(staffNote(), StaffNote.of(70, -1), reason: 'B flat');
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });
}
