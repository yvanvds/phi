import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/patcher/patch_port.dart';
import 'package:phi/domain/patcher/patch_port_id.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_ghost_cable.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end guard for issue #355: a patcher gesture whose pointer is torn
/// away mid-flight must leave **nothing** behind on the real canvas.
///
/// A cancelled pointer is what the window losing capture, a system drag, or a
/// dialog opening over the press all look like to Flutter: the pointer-up the
/// gesture was waiting for simply never arrives. Driven here through the real
/// [PhiApp] — real rail navigation, real surface composition beside the palette
/// and entity strip, real layout — because the artifacts this bug leaves are
/// painted *over the composed scene*: a marquee rectangle stuck across a node,
/// a ghost cable glued to the cursor, a node dropped somewhere nobody chose.
///
/// Backed by a [FakePatcherGateway], so no native `libyse.dll` is needed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: a cancelled gesture leaves no artifact and the canvas '
      'stays usable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: FakePatcherGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // The seed lays down slider → sine → dac, wired with two cables.
    final graph = engine.patcher.graph;
    PatchNode nodeOfType(String type) =>
        graph.nodes.firstWhere((n) => n.type == type);
    final slider = nodeOfType(Obj.gSlider);
    final sine = nodeOfType(Obj.dSine);

    final canvasTL = tester.getTopLeft(find.byType(PatcherCanvas));
    Offset portAt(PatchNode n, PatchPortSide side, int i) =>
        canvasTL +
        portPositionsFor(n)[PatchPortId(nodeId: n.id, side: side, index: i)]!;

    // The object box is the whole node since issue #379 — its middle is where
    // a body drag is aimed, there being no header any more.
    final sineLine = find.text('sine 440');
    final sineHeaderCentre =
        canvasTL +
        sine.position +
        Offset(sine.size.width / 2, sine.size.height / 2);
    final sineStart = sine.position;
    final sineDrawnAtStart = tester.getTopLeft(sineLine);

    // The seed wires its cables with the non-journaled primitive, so the undo
    // stack starts empty — anything on it later came from a gesture.
    expect(engine.patcher.undoScope.canUndo, isFalse);

    // ── a cable drag torn away mid-flight ─────────────────────────────────
    final cable = await tester.startGesture(
      portAt(slider, PatchPortSide.output, 0),
    );
    await tester.pump();
    await cable.moveTo(canvasTL + const Offset(420, 430));
    await tester.pump();
    expect(find.byType(PatcherGhostCable), findsOneWidget);

    await cable.cancel();
    await tester.pumpAndSettle();

    // No ghost left trailing the cursor, and no cable was invented from a drop
    // that never happened.
    expect(find.byType(PatcherGhostCable), findsNothing);
    expect(graph.dragSourcePort, isNull);
    expect(graph.cables, hasLength(2));

    // ── a body drag torn away mid-flight ──────────────────────────────────
    //
    // This also proves the canvas is not left inert: while a cable source is
    // stuck the canvas swallows every press, so this drag would do nothing.
    final drag = await tester.startGesture(sineHeaderCentre);
    await tester.pump();
    await drag.moveBy(const Offset(70, 45));
    await tester.pump();
    // Mid-gesture the node really is being dragged — the preview followed.
    expect(
      tester.getTopLeft(sineLine),
      sineDrawnAtStart + const Offset(70, 45),
    );

    await drag.cancel();
    await tester.pumpAndSettle();

    // The abandoned gesture is undone, not committed: the node is drawn back at
    // its origin and nothing reached the undo stack.
    expect(sine.position, sineStart);
    expect(tester.getTopLeft(sineLine), sineDrawnAtStart);
    expect(engine.patcher.undoScope.canUndo, isFalse);

    // ── a marquee torn away mid-flight ────────────────────────────────────
    //
    // The drag above left the sine selected (dragging a node selects it), so
    // the guard is that the abandoned marquee changes the selection at all —
    // it is dragged right across the slider, which a completed one would add.
    final selectedBefore = {...graph.selectedNodes};
    final marquee = await tester.startGesture(canvasTL + const Offset(30, 40));
    await tester.pump();
    await marquee.moveTo(canvasTL + const Offset(360, 420));
    await tester.pump();
    expect(find.byKey(PatcherCanvas.marqueeKey), findsOneWidget);

    await marquee.cancel();
    await tester.pumpAndSettle();

    // The grey rubber-band rectangle — the artifact reported in issue #355 —
    // is gone from the composed scene, and it selected nothing on its way out.
    expect(find.byKey(PatcherCanvas.marqueeKey), findsNothing);
    expect(graph.selectedNodes, selectedBefore);
    expect(graph.isNodeSelected(slider.id), isFalse);

    // ── and the canvas still works, immediately ───────────────────────────
    final again = await tester.startGesture(sineHeaderCentre);
    await tester.pump();
    await again.moveBy(const Offset(40, 25));
    await tester.pump();
    await again.up();
    await tester.pumpAndSettle();

    expect(sine.position, sineStart + const Offset(40, 25));
    expect(
      tester.getTopLeft(sineLine),
      sineDrawnAtStart + const Offset(40, 25),
    );
    expect(engine.patcher.undoScope.canUndo, isTrue);

    session.dispose();
    await engine.dispose();
  });
}
