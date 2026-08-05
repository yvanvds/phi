import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the canvas interaction polish (issue #359), driven
/// through the real [PhiApp] — real rail navigation, real panes, real focus
/// tree, real fonts and layout — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched.
///
/// A widget test cannot stand in for this one. Two of the three legs live
/// precisely in the *composition*: the hover cursor is resolved by the
/// framework's mouse tracker against the whole hit-test path, so every
/// `MouseRegion` the shell wraps the surface in gets a vote and only the real
/// stack has them; and the number scrub has to survive the canvas's own raw
/// pointer pipeline, the surface's poll and the app-level text shortcuts all
/// being stacked above a field that a press must still be able to reach.
///
/// The scrub leg runs in **run mode** (issue #378): with the node header gone,
/// a GUI body that owned its own presses would leave a fader unmovable, so the
/// canvas switches every body off in `edit` mode and a number box only scrubs
/// while the patch is being played. The hover and the cable detach are editing,
/// and stay on either side of it in `edit` — the mode is flipped from the
/// placement bar, exactly as a user flips it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  PatchPortId out(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.output, index: i);
  PatchPortId inp(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.input, index: i);

  testWidgets('patcher: a port rings on hover, a number box scrubs, and a '
      'cable detaches onto nothing', (tester) async {
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

    // Start from an empty canvas. The demo seed is not what this test is
    // about, and its nodes and cables would sit over the ones that are.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();
    expect(patcher.graph.cables, isEmpty);

    // Three nodes of our own near the scene origin, so they are certainly on
    // screen whatever the panes around the canvas cost.
    final registry = NodeTypeRegistry.instance;
    patcher.addNode(
      desc: registry.find(Obj.gFloat)!,
      position: const Offset(40, 20),
    );
    final slider = patcher.addNode(
      desc: registry.find(Obj.gSlider)!,
      position: const Offset(40, 130),
    );
    final sine = patcher.addNode(
      desc: registry.find(Obj.dSine)!,
      position: const Offset(240, 130),
    );
    patcher.connect(out(slider, 0), inp(sine, 0));
    await tester.pumpAndSettle();
    expect(patcher.graph.cables, hasLength(1));

    final canvasTL = tester.getTopLeft(find.byType(PatcherCanvas));
    Offset globalOf(Offset scene) => canvasTL + scene;
    Offset portOf(PatchPortId id) {
      final node = patcher.graph.nodeById(id.nodeId)!;
      return portPositionsFor(node)[id]!;
    }

    // ── 1) hovering a port rings it and takes the crosshair ─────────────────
    expect(find.byKey(PatcherCanvas.portHoverKey), findsNothing);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(() => pointer.removePointer());
    await tester.pumpAndSettle();

    await pointer.moveTo(globalOf(portOf(inp(sine, 0))));
    await tester.pumpAndSettle();

    expect(find.byKey(PatcherCanvas.portHoverKey), findsOneWidget);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.precise,
    );

    // Off the port again and the affordance goes with it — a ring left behind
    // would be worse than none at all.
    await pointer.moveTo(globalOf(portOf(inp(sine, 0)) + const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(find.byKey(PatcherCanvas.portHoverKey), findsNothing);

    // ── 2) dragging the .f readout scrubs its value ─────────────────────────
    final field = find.descendant(
      of: find.byType(NumberNodeBody),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);
    String shown() => tester.widget<TextField>(field).controller!.text;
    expect(shown(), '0');

    PatchCanvasMode mode() =>
        tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode;
    Future<void> flipMode() async {
      await tester.tap(find.byKey(PatchPlacementBar.modeKey));
      await tester.pumpAndSettle();
    }

    // Play the patch: only then is the body live and the readout a control at
    // all (issue #378).
    expect(mode(), PatchCanvasMode.edit);
    await flipMode();
    expect(mode(), PatchCanvasMode.run);

    final scrub = await tester.startGesture(
      tester.getCenter(field),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // The first leg spends the slop; the second is the value.
    await scrub.moveBy(const Offset(0, -6));
    await tester.pump();
    await scrub.moveBy(const Offset(0, -25));
    await tester.pump();
    await scrub.up();
    await tester.pumpAndSettle();

    expect(
      patcherGateway.calls.where((c) => c.endsWith(':0:25.000')),
      isNotEmpty,
    );
    // The box shows what the engine reports back, and it is not stuck in edit
    // mode: a scrub is not a click, so the caret stayed away.
    expect(shown(), '25');
    expect(tester.widget<TextField>(field).focusNode!.hasPrimaryFocus, isFalse);

    // ── 3) a cable grabbed near its end and dropped on nothing is deleted ───
    // Back to editing: re-routing a cable is an edit, and a patch being played
    // cannot be rewired (issue #378).
    await flipMode();
    expect(mode(), PatchCanvasMode.edit);

    expect(patcher.graph.cables, hasLength(1));
    final a = portOf(out(slider, 0));
    final b = portOf(inp(sine, 0));
    // On the wire, past the port's own press radius, inside the grab band.
    var grab = b;
    for (var i = 1; i < 60; i++) {
      final p = PatchCableGeometry.pointAt(a, b, 1 - i / 60);
      final d = (p - b).distance;
      if (d > PatchCanvasConstants.portPressRadius + 2 &&
          d < PatchCanvasConstants.cableGrabRadius - 2) {
        grab = p;
        break;
      }
    }
    expect(grab, isNot(b));

    final detach = await tester.startGesture(globalOf(grab));
    await tester.pump();
    await detach.moveTo(globalOf(const Offset(120, 260)));
    await tester.pump();
    expect(patcher.graph.cables, isEmpty);

    await detach.up();
    await tester.pumpAndSettle();
    expect(patcher.graph.cables, isEmpty);
    expect(patcherGateway.cables, isEmpty);

    // Journaled: the canvas took the keyboard back on release, so Ctrl+Z
    // reaches the patcher's own undo scope and re-wires it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(patcher.graph.cables, hasLength(1));
    expect(patcherGateway.cables, hasLength(1));

    session.dispose();
    await engine.dispose();
  });
}
