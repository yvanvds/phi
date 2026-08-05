import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_cable_geometry.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_port_dot.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that inlets sit on a node's **top** edge and outlets on its
/// **bottom** one (issue #377), driven through the real [PhiApp] — real rail
/// navigation, real panes, real fonts and layout — backed by a
/// [FakePatcherGateway] so no native `libyse.dll` is touched.
///
/// A widget test cannot stand in for this one. Where the dots are *drawn* is a
/// question about the composed node — the frame inside its `Positioned` inside
/// the canvas's transform inside the shell's panes — and every one of those
/// layers has a say in the rect the ports are measured against. And the leg
/// that matters most, authoring a cable from one box's bottom edge into the
/// next box's top edge, runs through the canvas's raw pointer pipeline against
/// the same scene-space hit-tests the cursor previews; only the real stack has
/// them stacked in the order a user meets them.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Finder viewOf(PatchNode n) =>
      find.byWidgetPredicate((w) => w is PatcherNodeView && w.node.id == n.id);

  Finder dotsOf(PatchNode n) =>
      find.descendant(of: viewOf(n), matching: find.byType(PatchPortDot));

  PatchPortId out(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.output, index: i);
  PatchPortId inp(PatchNode n, int i) =>
      PatchPortId(nodeId: n.id, side: PatchPortSide.input, index: i);

  testWidgets('patcher: ports sit on the horizontal edges, and a cable drops '
      'out of one box into the top of the next', (tester) async {
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
    PatchNode nodeOfType(String type) =>
        patcher.graph.nodes.firstWhere((n) => n.type == type);

    // ── 1) the patch that was already there loads with every cable intact ────
    //
    // Ports are computed from the live topology the gateway reports and only
    // node *positions* persist, so moving the ports migrates nothing: the seed
    // graph is the stand-in for a patch saved before this change.
    expect(patcher.graph.nodes, hasLength(3));
    expect(patcher.graph.cables, hasLength(2));
    expect(patcherGateway.cables, hasLength(2));

    // ── 2) the dots are *drawn* on the top and bottom edges ─────────────────
    final sine = nodeOfType(Obj.dSine);
    final sineBox = tester.getRect(viewOf(sine));
    expect(dotsOf(sine), findsNWidgets(2)); // one inlet, one outlet

    final sineInlet = tester.getCenter(dotsOf(sine).at(0));
    final sineOutlet = tester.getCenter(dotsOf(sine).at(1));
    expect(sineInlet.dy, moreOrLessEquals(sineBox.top, epsilon: 0.01));
    expect(sineOutlet.dy, moreOrLessEquals(sineBox.bottom, epsilon: 0.01));
    expect(
      sineInlet.dx,
      moreOrLessEquals(
        sineBox.left + PatchCanvasConstants.firstPortOffset,
        epsilon: 0.01,
      ),
    );
    // Both dots are well inside the box horizontally: nothing hangs off the
    // vertical edges any more.
    expect(sineInlet.dx, lessThan(sineBox.right));
    expect(sineOutlet.dx, moreOrLessEquals(sineInlet.dx, epsilon: 0.01));

    // A two-inlet object spreads them *along* the top edge — the whole point of
    // the move: the port count now costs width, which a line of text absorbs,
    // instead of the height that made a one-line box impossible.
    final dac = nodeOfType(Obj.dDac);
    final dacBox = tester.getRect(viewOf(dac));
    expect(dotsOf(dac), findsNWidgets(2));
    final dacLeft = tester.getCenter(dotsOf(dac).at(0));
    final dacRight = tester.getCenter(dotsOf(dac).at(1));
    expect(dacLeft.dy, moreOrLessEquals(dacBox.top, epsilon: 0.01));
    expect(dacRight.dy, moreOrLessEquals(dacBox.top, epsilon: 0.01));
    expect(
      dacRight.dx - dacLeft.dx,
      moreOrLessEquals(PatchCanvasConstants.portSpacing, epsilon: 0.01),
    );
    expect(dacRight.dx, lessThan(dacBox.right));

    // ── 3) author a cable, bottom edge to top edge ──────────────────────────
    //
    // A canvas of our own: two boxes stacked, so the gesture is exactly the one
    // the design describes — out of the bottom of one, into the top of the next.
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();
    expect(patcher.graph.cables, isEmpty);

    final registry = NodeTypeRegistry.instance;
    final slider = patcher.addNode(
      desc: registry.find(Obj.gSlider)!,
      position: const Offset(40, 10),
    );
    final target = patcher.addNode(
      desc: registry.find(Obj.dSine)!,
      position: const Offset(40, 280),
    );
    await tester.pumpAndSettle();

    final canvasTL = tester.getTopLeft(find.byType(PatcherCanvas));
    Offset globalOf(Offset scene) => canvasTL + scene;

    final from = portPositionsFor(slider)[out(slider, 0)]!;
    final to = portPositionsFor(target)[inp(target, 0)]!;
    // The gesture really does run downward, from one box's underside to the
    // other's top — not sideways between facing edges.
    expect(from.dy, slider.position.dy + slider.size.height);
    expect(to.dy, target.position.dy);
    expect(to.dy, greaterThan(from.dy));

    final drag = await tester.startGesture(globalOf(from));
    await tester.pump();
    await drag.moveTo(globalOf(Offset.lerp(from, to, 0.5)!));
    await tester.pump();
    await drag.moveTo(globalOf(to));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(patcher.graph.cables, hasLength(1));
    expect(patcher.graph.cables.single.source, out(slider, 0));
    expect(patcher.graph.cables.single.target, inp(target, 0));
    expect(patcherGateway.cables, hasLength(1));

    // ── 4) the wire that was painted is the wire that can be clicked ────────
    //
    // Painter and hit-test share one cubic, so a click on the curve between the
    // boxes — well clear of either endpoint's grab band — selects the cable.
    final mid = PatchCableGeometry.pointAt(from, to, 0.5);
    expect(
      (mid - from).distance,
      greaterThan(PatchCanvasConstants.cableGrabRadius),
    );
    expect(
      (mid - to).distance,
      greaterThan(PatchCanvasConstants.cableGrabRadius),
    );
    await tester.tapAt(globalOf(mid));
    await tester.pumpAndSettle();
    expect(patcher.graph.selectedCable, patcher.graph.cables.single);

    // ── 5) and the whole thing is one journaled step ────────────────────────
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(patcher.graph.cables, isEmpty);
    expect(patcherGateway.cables, isEmpty);

    session.dispose();
    await engine.dispose();
  });
}
