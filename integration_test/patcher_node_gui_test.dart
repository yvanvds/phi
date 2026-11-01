import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_dial_knob.dart';
import 'package:phi/design/widgets/patcher/patch_function_graph.dart';
import 'package:phi/design/widgets/patcher/patch_incdec_stepper.dart';
import 'package:phi/design/widgets/patcher/patch_keyboard.dart';
import 'package:phi/design/widgets/patcher/patch_led_lamp.dart';
import 'package:phi/design/widgets/patcher/patch_list_box.dart';
import 'package:phi/design/widgets/patcher/patch_matrix_grid.dart';
import 'package:phi/design/widgets/patcher/patch_menu_box.dart';
import 'package:phi/design/widgets/patcher/patch_nodes_field.dart';
import 'package:phi/design/widgets/patcher/patch_preset_grid.dart';
import 'package:phi/design/widgets/patcher/patch_radio_group.dart';
import 'package:phi/design/widgets/patcher/patch_range_bar.dart';
import 'package:phi/design/widgets/patcher/patch_slider_bank.dart';
import 'package:phi/design/widgets/patcher/patch_staff.dart';
import 'package:phi/design/widgets/patcher/patch_tab_strip.dart';
import 'package:phi/design/widgets/patcher/patch_text_button.dart';
import 'package:phi/design/widgets/patcher/patch_text_edit_box.dart';
import 'package:phi/design/widgets/patcher/patch_xy_pad.dart';
import 'package:phi/domain/patcher/field_node.dart';
import 'package:phi/domain/patcher/keyboard_layout.dart';
import 'package:phi/domain/patcher/nodes_view.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_payload.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/patcher/patch_port_kind.dart';
import 'package:phi/domain/patcher/preset_grid.dart';
import 'package:phi/domain/patcher/staff_note.dart';
import 'package:phi/domain/project/app_settings/app_settings_controller.dart';
import 'package:phi/domain/project/entity_address.dart';
import 'package:phi/domain/project/lifecycle/project_controller.dart';
import 'package:phi/domain/project/project_registry.dart';
import 'package:phi/domain/project/registry_kinds.dart';
import 'package:phi/domain/project/registry_seed.dart';
import 'package:phi/domain/project/store/registry_codecs.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/bridge/patcher_node_snapshot.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/gui_value_read.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/nodes/list_node_body.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_keyboard_settings.dart';
import 'package:yse/yse.dart';

import '../test/domain/project/test_doubles/fake_app_settings_store.dart';
import '../test/domain/project/test_doubles/fake_journal_store.dart';
import '../test/domain/project/test_doubles/fake_project_directory_picker.dart';
import '../test/domain/project/test_doubles/fake_project_store.dart';
import '../test/engine/test_doubles/fake_midi_gateway.dart';
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

  testWidgets('a .b flashes on each bang that arrives over a cable in run '
      'mode (issue #519)', (tester) async {
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
    final d = NodeTypeRegistry.instance.find(Obj.gButton)!;
    final bang = patcher.addNode(desc: d, position: const Offset(60, 60));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    bool lit() =>
        tester.widget<PatchBangSquare>(find.byType(PatchBangSquare)).flash;
    expect(lit(), isFalse);

    // Two ticks, the way a `.metro` delivers them: each bang lands on the
    // native object with nothing said to the canvas, and the live poller must
    // light the button for each one.
    for (var tick = 0; tick < 2; tick++) {
      patcherGateway.sendBang(patcher.instanceId, bang.id.value, 0);
      var flashed = false;
      for (var i = 0; i < 50 && !flashed; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        flashed = lit();
      }
      expect(flashed, isTrue, reason: 'tick $tick lit the button');

      // ...briefly: the read consumed the press, so it goes dark again.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(lit(), isFalse, reason: 'tick $tick went dark');
    }

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

  testWidgets('a selected .kslider takes its range and a fixed velocity from '
      'the reference panel, each one undo step (issue #515)', (tester) async {
    final patcherGateway = FakePatcherGateway()
      // The reference panel documents only what the engine catalogues.
      ..objectTypesCatalogue = [
        ...FakePatcherGateway.defaultCatalogue,
        const PatchObjectDescriptor(
          type: Obj.gKslider,
          description: 'piano keyboard',
          category: PatchObjectCategory.gui,
          isDsp: false,
          inlets: [],
          outlets: [],
          params: [],
        ),
      ];
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
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();
    patcher.undoScope.clear();

    final keys = patcher.addNode(
      desc: NodeTypeRegistry.instance.find(Obj.gKslider)!,
      position: const Offset(30, 30),
    );
    await tester.pumpAndSettle();

    PatchKeyboard keyboard() =>
        tester.widget<PatchKeyboard>(find.byType(PatchKeyboard));
    double keyboardWidth() => tester.getSize(find.byType(PatchKeyboard)).width;
    String? rangeShown() =>
        tester.widget<Text>(find.byKey(PatchKeyboardSettings.rangeKey)).data;
    Future<void> step(String name) async {
      await tester.tap(find.byKey(PatchKeyboardSettings.stepKey(name)));
      await tester.pumpAndSettle();
    }

    Future<void> chord(LogicalKeyboardKey mod, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(mod);
      await tester.pumpAndSettle();
    }

    final standardWidth = keyboardWidth();
    expect(keyboard().layout.low, KeyboardLayout.defaultLow);

    // ─── select it: the panel shows its keyboard rows ─────────────────────
    await tester.tapAt(tester.getCenter(find.byType(PatchKeyboard)));
    await tester.pumpAndSettle();
    expect(find.text('KEYBOARD'), findsOneWidget);
    expect(rangeShown(), 'C3 – C6');

    // ─── shift up an octave, then widen down two ──────────────────────────
    await step('shift.up');
    expect((keyboard().layout.low, keyboard().layout.high), (60, 96));
    expect(rangeShown(), 'C4 – C7');
    expect(keyboardWidth(), standardWidth, reason: 'as many keys as before');

    await step('low.down');
    await step('low.down');
    expect(keyboard().layout.low, 36);
    expect(rangeShown(), 'C2 – C7');
    expect(
      keyboardWidth(),
      closeTo(standardWidth * 36 / 22, 0.01),
      reason: 'the box follows the range',
    );
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    // ─── each step is one undo: the keyboard walks back ───────────────────
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(keyboard().layout.low, 48);
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(keyboard().layout.low, KeyboardLayout.defaultLow);
    expect(keyboard().layout.high, KeyboardLayout.defaultHigh);
    expect(keyboardWidth(), standardWidth);
    expect(rangeShown(), 'C3 – C6');
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY);
    expect(keyboard().layout.low, 60);

    // ─── a fixed velocity: every press in run mode plays at it ────────────
    await step('velocity.fixed');
    await step('velocity.+10');
    expect(
      tester.widget<Text>(find.byKey(PatchKeyboardSettings.velocityKey)).data,
      '110',
    );
    expect(patcher.keyboardVelocityOf(keys.id), 110);

    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    Offset keyAt(int pitch, double y) {
      final box = tester.getRect(find.byType(PatchKeyboard));
      final b = keyboard().layout.boundsOf(pitch);
      return box.topLeft +
          Offset(box.width * (b.left + b.right) / 2, box.height * y);
    }

    patcherGateway.calls.clear();
    await tester.tapAt(keyAt(64, 0.05));
    await tester.pumpAndSettle();
    final sends = [
      for (final c in patcherGateway.calls)
        if (c.startsWith('sendList:${keys.id.value}:0:')) c.split(':').last,
    ];
    expect(sends, ['set 64 110', 'set 64 0'], reason: 'not by depth');

    // ─── and back to depth, undoably ──────────────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    await step('velocity.depth');
    expect(patcher.keyboardVelocityOf(keys.id), isNull);
    await chord(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(patcher.keyboardVelocityOf(keys.id), 110);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('a .matrixctrl renders its grid, toggles a cell in run mode and '
      'sends it down outlet 0 as <column> <row> <value> (issue #474)', (
    tester,
  ) async {
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

    // An empty canvas: the demo seed would sit over the control under test.
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

    final gridNode = gui(Obj.gMatrixctrl, const Offset(40, 40), args: '6 4');
    final list = gui(Obj.gList, const Offset(40, 220));
    patcher.connect(
      PatchPortId(nodeId: gridNode.id, side: PatchPortSide.output, index: 0),
      PatchPortId(nodeId: list.id, side: PatchPortSide.input, index: 0),
    );
    await tester.pumpAndSettle();

    // ─── it renders as its grid, at its configured size ────────────────────
    PatchMatrixGrid grid() =>
        tester.widget<PatchMatrixGrid>(find.byType(PatchMatrixGrid));
    expect(find.byType(PatchMatrixGrid), findsOneWidget);
    expect(grid().columns, 6);
    expect(grid().rows, 4);
    expect(grid().values, everyElement(0));
    final rect = tester.getRect(find.byType(PatchMatrixGrid));
    expect(rect.width / rect.height, closeTo(6 / 4, 0.01));
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    final handle = patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == Obj.gMatrixctrl)
        .key;
    List<String> listsTo() => [
      for (final c in patcherGateway.calls)
        if (c.startsWith('sendList:$handle:0:'))
          c.substring('sendList:$handle:0:'.length),
    ];
    String listShows() => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(ListNodeBody),
            matching: find.byType(Text),
          ),
        )
        .data!;
    Offset cellAt(int column, int row) {
      final box = tester.getRect(find.byType(PatchMatrixGrid));
      return box.topLeft +
          Offset(box.width * (column + 0.5) / 6, box.height * (row + 0.5) / 4);
    }

    // ─── edit mode: a press on the grid moves the node, writes nothing ─────
    patcherGateway.calls.clear();
    final before = gridNode.position;
    await tester.dragFrom(cellAt(2, 1), const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(gridNode.position, isNot(before), reason: 'the drag moved the node');
    expect(listsTo(), isEmpty);
    expect(grid().values, everyElement(0));

    // ─── run mode: a click toggles the cell and sends it on ────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    patcherGateway.calls.clear();
    await tester.tapAt(cellAt(2, 1));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    // Column 2, row 1 of a 4-row grid is cell 9.
    expect(listsTo(), ['set 9 1']);
    expect(grid().values[9], 1);
    expect(listShows(), '2 1 1', reason: 'outlet 0 reached the .l');

    // A drag paints along a row.
    patcherGateway.calls.clear();
    final stroke = await tester.startGesture(cellAt(0, 3));
    for (var c = 1; c < 6; c++) {
      await stroke.moveTo(cellAt(c, 3));
      await tester.pump();
    }
    await stroke.up();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(listsTo(), hasLength(6));
    expect(
      [for (var c = 0; c < 6; c++) grid().values[c * 4 + 3]],
      [1, 1, 1, 1, 1, 1],
    );
    expect(listShows(), '5 3 1');

    // ─── a cable-driven change repaints the cell ───────────────────────────
    patcherGateway.sendList(patcher.instanceId, handle, 0, '2 1 0');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(grid().values[9], 0);
    expect(listShows(), '2 1 0');
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });
  testWidgets('a .function is drawn on the canvas in run mode, bangs its ramp '
      'into a .line, and keeps its points through a reload (issue #475)', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway()
      // The engine's `.line`: target-and-time in, the ramp out.
      ..topologyOverrides[Obj.gLine] = const PatcherNodeSnapshot(
        inputs: 2,
        outputs: 2,
        inputKinds: [PatchPortKind.control, PatchPortKind.control],
        outputKinds: [PatchPortKind.control, PatchPortKind.control],
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

    // An empty canvas: the demo seed would sit over the control under test.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    PatchNode gui(String type, Offset position) {
      final d = NodeTypeRegistry.instance.find(type);
      return patcher.addNode(
        desc: NodeDescriptor(
          type: type,
          defaultSize: d?.defaultSize,
          defaultArgs: '',
          inputs: d?.inputs ?? const [PortSpec(kind: PatchPortKind.control)],
          outputs: d?.outputs ?? const [PortSpec(kind: PatchPortKind.control)],
          buildBody: d?.buildBody,
          readsGuiValue: d?.readsGuiValue ?? false,
          guiValueRead: d?.guiValueRead ?? GuiValueRead.whole,
        ),
        position: position,
      );
    }

    final fnNode = gui(Obj.gFunction, const Offset(40, 40));
    final line = gui(Obj.gLine, const Offset(40, 240));
    patcher.connect(
      PatchPortId(nodeId: fnNode.id, side: PatchPortSide.output, index: 1),
      PatchPortId(nodeId: line.id, side: PatchPortSide.input, index: 0),
    );
    await tester.pumpAndSettle();

    // ─── it renders as its editor, at its tuned size ───────────────────────
    PatchFunctionGraph graph() =>
        tester.widget<PatchFunctionGraph>(find.byType(PatchFunctionGraph));
    expect(find.byType(PatchFunctionGraph), findsOneWidget);
    expect(graph().positions, isEmpty);
    final rect = tester.getRect(find.byType(PatchFunctionGraph));
    expect(rect.width / rect.height, closeTo(2, 0.01));
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    final handle = patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == Obj.gFunction)
        .key;
    final lineHandle = patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == Obj.gLine)
        .key;
    List<String> sentTo() => [
      for (final c in patcherGateway.calls)
        for (final verb in const ['sendList', 'sendMessage'])
          if (c.startsWith('$verb:$handle:0:'))
            c.substring('$verb:$handle:0:'.length),
    ];
    Offset plotAt(double x, double y) {
      final box = tester.getRect(find.byType(PatchFunctionGraph));
      const inset = PatchFunctionGraph.inset;
      return box.topLeft +
          Offset(
            inset + x * (box.width - 2 * inset),
            inset + (1 - y) * (box.height - 2 * inset),
          );
    }

    Future<void> click(double x, double y) async {
      await tester.tapAt(plotAt(x, y));
      // Past the double-click window, so each click stands alone.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    // ─── edit mode: a press on the editor moves the node, writes nothing ───
    patcherGateway.calls.clear();
    final before = fnNode.position;
    await tester.dragFrom(plotAt(0.5, 0.5), const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(fnNode.position, isNot(before), reason: 'the drag moved the node');
    expect(sentTo(), isEmpty);
    expect(graph().positions, isEmpty);

    // ─── run mode: draw a three-point envelope ─────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    patcherGateway.calls.clear();
    await click(0, 0);
    await click(1, 1);
    await click(0.5, 0.5);
    expect(sentTo(), ['0 0', '1000 1', '500 0.5']);
    expect(graph().positions, [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0)]);

    // Drag the middle point left.
    final drag = await tester.startGesture(plotAt(0.5, 0.5));
    await drag.moveTo(plotAt(0.4, 0.5));
    await tester.pump();
    await drag.moveTo(plotAt(0.25, 0.5));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(sentTo().last, 'set 1 250 0.5');
    expect(graph().positions[1], (0.25, 0.5));

    // Alt-drag the rising segment into it upwards: an early, negative curve.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final bendAt = plotAt(0.6, 0.5);
    final bend = await tester.startGesture(bendAt);
    await bend.moveTo(bendAt - const Offset(0, 50));
    await tester.pump();
    await bend.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(sentTo().last, 'setcurve 2 -0.5');
    expect(graph().curves, [0, 0, -0.5]);

    // A fourth point, removed again with Delete — the key reaches the body
    // through the canvas, and does not delete the node.
    await click(0.75, 0.25);
    expect(sentTo().last, '750 0.25');
    expect(graph().positions, hasLength(4));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(sentTo().last, 'clear 2');
    expect(graph().positions, hasLength(3));
    expect(patcher.graph.nodes, hasLength(2), reason: 'the node is still here');

    // ─── a bang sends the ramp into the .line ──────────────────────────────
    patcherGateway.calls.clear();
    patcher.setControlBang(fnNode.id, inlet: 0);
    await tester.pumpAndSettle();
    expect(
      patcherGateway.calls,
      contains('sendList:$lineHandle:0:0 0 0.5 250 1 750'),
    );

    // ─── the points survive save and reload ────────────────────────────────
    // Duplicating flushes the live dump to the patch's payload and opens the
    // copy from it, as a reload does.
    final library = engine.patchLibrary;
    library.duplicate(library.openAddress!);
    await tester.pumpAndSettle();
    expect(library.openAddress!.name, endsWith('_copy'));
    expect(find.byType(PatchFunctionGraph), findsOneWidget);
    expect(graph().positions, [(0.0, 0.0), (0.25, 0.5), (1.0, 1.0)]);
    expect(graph().curves, [0, 0, -0.5]);
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('a .nodes field is laid out and played in run mode: the cursor '
      'dragged into one node sends it a weight of 1 (issue #476)', (
    tester,
  ) async {
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

    // An empty canvas: the demo seed would sit over the control under test.
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

    final fieldNode = gui(Obj.gNodes, const Offset(40, 40), args: '2');
    final list = gui(Obj.gList, const Offset(40, 260));
    patcher.connect(
      PatchPortId(nodeId: fieldNode.id, side: PatchPortSide.output, index: 0),
      PatchPortId(nodeId: list.id, side: PatchPortSide.input, index: 0),
    );
    await tester.pumpAndSettle();

    // ─── it renders as its field, square, two unit nodes at the origin ─────
    PatchNodesField field() =>
        tester.widget<PatchNodesField>(find.byType(PatchNodesField));
    expect(find.byType(PatchNodesField), findsOneWidget);
    expect(field().nodes, List.filled(2, const FieldNode(0, 0, 1)));
    final rect = tester.getRect(find.byType(PatchNodesField));
    expect(rect.width / rect.height, closeTo(1, 0.01));
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    final handle = patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == Obj.gNodes)
        .key;
    List<String> sentTo() => [
      for (final c in patcherGateway.calls)
        if (c.startsWith('sendList:$handle:0:'))
          c.substring('sendList:$handle:0:'.length),
    ];
    String listShows() => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(ListNodeBody),
            matching: find.byType(Text),
          ),
        )
        .data!;
    Offset fieldAt(double x, double y) {
      final box = tester.getRect(find.byType(PatchNodesField));
      final (px, py) = NodesView(
        width: box.width,
        height: box.height,
      ).toPixel(x, y);
      return box.topLeft + Offset(px, py);
    }

    Future<void> drag(Offset from, Offset to, {bool alt = false}) async {
      if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final pointer = await tester.startGesture(from);
      await tester.pump();
      await pointer.moveTo(Offset.lerp(from, to, 0.5)!);
      await tester.pump();
      await pointer.moveTo(to);
      await tester.pump();
      await pointer.up();
      if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // ─── a layout driven over a cable redraws the field ────────────────────
    patcherGateway.sendList(
      patcher.instanceId,
      handle,
      0,
      '0.25 0.25 0.2 0.75 0.75 0.2',
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(field().nodes, const [
      FieldNode(0.25, 0.25, 0.2),
      FieldNode(0.75, 0.75, 0.2),
    ]);

    // ─── edit mode: a press on the field moves the node, writes nothing ────
    patcherGateway.calls.clear();
    final before = fieldNode.position;
    await tester.dragFrom(fieldAt(0.5, 0.5), const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(fieldNode.position, isNot(before), reason: 'the drag moved the box');
    expect(sentTo(), isEmpty);

    // ─── run mode ──────────────────────────────────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    // Alt-drag node 2 in from the corner, then its rim out to widen it.
    patcherGateway.calls.clear();
    await drag(fieldAt(0.75, 0.75), fieldAt(0.6, 0.6), alt: true);
    expect(sentTo().last, 'set 1 0.6 0.6');
    await drag(fieldAt(0.8, 0.6), fieldAt(0.9, 0.6), alt: true);
    expect(sentTo().last, 'set 1 0.6 0.6 0.3');
    expect(field().nodes[1], const FieldNode(0.6, 0.6, 0.3));
    expect(
      patcherGateway.nodes[handle]!.guiCells[1],
      '0.6 0.6 0.3',
      reason: 'the layout lives in the object, read back as its GUI value',
    );

    // Drag the cursor from outside every node into node 2 alone.
    patcherGateway.calls.clear();
    await drag(fieldAt(0.5, 0.05), fieldAt(0.6, 0.65));
    expect(sentTo().first, '0.5 0.05');
    expect(sentTo().last, '0.6 0.65');
    expect(listShows(), '0 1', reason: 'node 2 takes the whole weight');
    expect(field().cursor, (0.6, 0.65));
    expect(field().weights, [0, 1]);

    // Out of every node, the weights all fall to 0.
    await drag(fieldAt(0.6, 0.65), fieldAt(0.05, 0.95));
    expect(listShows(), '0 0');
    expect(field().weights, [0, 0]);
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });

  // ─── the preset bank (issue #477) ─────────────────────────────────────────

  /// The centre of [slot]'s button in the one [PatchPresetGrid] on screen.
  Offset presetSlot(WidgetTester tester, int slot, {int slots = 32}) {
    final box = tester.getRect(find.byType(PatchPresetGrid));
    final grid = PresetGrid(slots: slots, width: box.width, height: box.height);
    final (x, y) = grid.originOf(slot);
    return box.topLeft +
        Offset(x + grid.cellWidth / 2, y + grid.cellHeight / 2);
  }

  /// Click [slot], holding [modifier] if given, and let the poll run.
  Future<void> clickSlot(
    WidgetTester tester,
    int slot, {
    LogicalKeyboardKey? modifier,
  }) async {
    if (modifier != null) await tester.sendKeyDownEvent(modifier);
    await tester.tapAt(presetSlot(tester, slot));
    if (modifier != null) await tester.sendKeyUpEvent(modifier);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  }

  testWidgets('a .preset stores a slider, and recalling the slot puts the '
      'slider back where it was (issue #477)', (tester) async {
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

    // An empty canvas: the demo seed would sit over the controls under test.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    PatchNode gui(String type, Offset position) {
      final d = NodeTypeRegistry.instance.find(type)!;
      return patcher.addNode(
        desc: NodeDescriptor(
          type: d.type,
          defaultSize: d.defaultSize,
          sizeForArgs: d.sizeForArgs,
          defaultArgs: '',
          inputs: d.inputs,
          outputs: d.outputs,
          buildBody: d.buildBody,
          readsGuiValue: d.readsGuiValue,
          guiValueRead: d.guiValueRead,
        ),
        position: position,
      );
    }

    gui(Obj.gSlider, const Offset(40, 40));
    final bankNode = gui(Obj.gPreset, const Offset(160, 40));
    await tester.pumpAndSettle();

    // ─── it renders as its slot grid, four rows of eight, all empty ────────
    PatchPresetGrid grid() =>
        tester.widget<PatchPresetGrid>(find.byType(PatchPresetGrid));
    PhiFader fader() => tester.widget<PhiFader>(find.byType(PhiFader));
    expect(find.byType(PatchPresetGrid), findsOneWidget);
    expect(grid().slots, 32);
    expect(grid().stored, isEmpty);
    expect(grid().active, -1);
    expect(tester.getSize(find.byType(PatchPresetGrid)).aspectRatio, 2);
    expect(tester.takeException(), isNull, reason: 'nothing overflows');

    final bank = patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == Obj.gPreset)
        .key;
    List<String> sentTo() => [
      for (final c in patcherGateway.calls)
        if (c.startsWith('sendMessage:$bank:0:'))
          c.substring('sendMessage:$bank:0:'.length),
    ];

    // ─── edit mode: a click on a slot moves the box and sends nothing ──────
    patcherGateway.calls.clear();
    final before = bankNode.position;
    await tester.dragFrom(presetSlot(tester, 1), const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(bankNode.position, isNot(before), reason: 'the drag moved the box');
    expect(sentTo(), isEmpty);

    // ─── run mode ──────────────────────────────────────────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    // A whole fader gesture: a body ignores the poll until the drag ends.
    Future<void> slide(double to) async {
      fader()
        ..onChanged(to)
        ..onChangeEnd?.call();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    // Move the slider, then Shift+click slot 1 to store it.
    await slide(0.3);
    patcherGateway.calls.clear();
    await clickSlot(tester, 1, modifier: LogicalKeyboardKey.shiftLeft);
    expect(sentTo(), ['store 1']);
    expect(grid().stored, {1});
    expect(grid().active, 1);

    // Move it again, then click slot 1: the slider shows the stored value.
    await slide(0.8);
    expect(fader().value, closeTo(0.8, 1e-9));
    await clickSlot(tester, 1);
    expect(sentTo().last, 'recall 1');
    expect(fader().value, closeTo(0.3, 1e-9), reason: 'recalled');
    expect(grid().active, 1);

    // Alt+click clears the slot, and with it the active marker.
    await clickSlot(tester, 1, modifier: LogicalKeyboardKey.altLeft);
    expect(sentTo().last, 'clear 1');
    expect(grid().stored, isEmpty);
    expect(grid().active, -1);
    expect(tester.takeException(), isNull);

    session.dispose();
    await engine.dispose();
  });

  testWidgets('a .preset opened from a saved project shows its stored slots, '
      'and recalling one moves the slider (issue #477)', (tester) async {
    final patchAddress = EntityAddress(
      kind: RegistryKinds.patch,
      segments: const ['presets'],
    );
    // A saved patch: a slider and a bank whose slot 2 holds it at 0.6, in
    // the dump's own spelling (each entry names its object by rank).
    void seed(ProjectRegistry registry) {
      seedDefaultProject(registry);
      registry.createEntity(
        patchAddress,
        payload: const PatchPayload(
          dump: {
            'objects': [
              {'id': 0, 'type': Obj.gSlider, 'args': '', 'x': 40.0, 'y': 40.0},
              {
                'id': 1,
                'type': Obj.gPreset,
                'args': '',
                'x': 160.0,
                'y': 40.0,
                'state': {
                  'slots': [
                    {
                      'slot': 2,
                      'objects': [
                        {'object': 0, 'type': Obj.gSlider, 'value': '0.6'},
                      ],
                    },
                  ],
                },
              },
            ],
            'cables': <Object?>[],
          },
        ).toJson(),
      );
    }

    final yse = FakeYseGateway();
    final engine = PhiEngine(
      yse,
      patcherGateway: FakePatcherGateway(),
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();
    final appSettings = AppSettingsController(FakeAppSettingsStore());
    final project = ProjectController(
      session: session,
      settings: appSettings,
      storeFactory: (_) => FakeProjectStore(codecs: defaultEntityCodecs()),
      journalStoreFactory: (_) => FakeJournalStore(),
      seedRegistry: seed,
      autosaveIntervalOverride: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      PhiApp(
        engine: engine,
        session: session,
        projectController: project,
        directoryPicker: FakeProjectDirectoryPicker(),
        autoStartProject: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(engine.patchLibrary.openAddress, patchAddress);
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    PatchPresetGrid grid() =>
        tester.widget<PatchPresetGrid>(find.byType(PatchPresetGrid));
    PhiFader fader() => tester.widget<PhiFader>(find.byType(PhiFader));
    expect(grid().stored, {2}, reason: 'the slots came back with the patch');
    expect(grid().active, -1, reason: 'loading recalls nothing');
    expect(fader().value, isNot(closeTo(0.6, 1e-9)));

    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    await clickSlot(tester, 2);
    expect(fader().value, closeTo(0.6, 1e-9));
    expect(grid().active, 2);
    expect(tester.takeException(), isNull);

    await engine.dispose();
    await yse.dispose();
    project.dispose();
    appSettings.dispose();
    session.dispose();
  });
}
