import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the patcher's **edit / run mode** (issue #378), driven
/// through the real [PhiApp]: real rail navigation, real panes, the real focus
/// tree, the real placement bar above the canvas, and the real seeded
/// `slider → ~sine → ~dac` patch — backed by a [FakePatcherGateway], so no
/// native `libyse.dll` is touched.
///
/// A widget test cannot stand in for this one. Every leg is a question about
/// the *composition* rather than about the canvas in isolation:
///
/// - Whether `Ctrl+E` reaches the canvas at all — instead of being eaten by the
///   shell's own focus scopes and app-level shortcuts on the way down — is
///   decided by the whole tree, and only the real one has all of it.
/// - The mode indicator lives in a *different widget* from the behaviour it
///   governs: it is chrome in the placement bar, and the canvas below only
///   changes what a press does if the surface actually threads the mode from
///   one to the other and back. A canvas test that passes the mode by hand
///   proves nothing about that wire.
/// - Whether a press on a real [PhiFader], inside a real node laid out by the
///   real canvas, reaches the fader or the node is exactly the arbitration the
///   mode exists to settle — and it is settled by widgets at three different
///   depths of the real tree.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: edit mode drags a slider from its fader, run mode '
      'plays it, and Ctrl+E flips between them', (tester) async {
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
    final slider = patcher.graph.nodes.firstWhere((n) => n.type == Obj.gSlider);
    // Near the scene origin, so the whole node is certainly on screen whatever
    // the strip, palette and reference panel around the canvas cost.
    const start = Offset(40, 40);
    patcher.placeNode(slider.id, start);
    await tester.pumpAndSettle();

    PatchCanvasMode canvasMode() =>
        tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode;
    List<String> sendFloats() =>
        patcherGateway.calls.where((c) => c.startsWith('sendFloat')).toList();

    final fader = find.byType(PhiFader);
    expect(fader, findsOneWidget);
    expect(canvasMode(), PatchCanvasMode.edit);
    expect(find.text('EDIT'), findsOneWidget);

    // ── 1) edit mode: the fader is inert, and a drag on it moves the node ────
    patcherGateway.calls.clear();
    var g = await tester.startGesture(tester.getCenter(fader));
    await tester.pump();
    await g.moveBy(const Offset(30, 24));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    // With the header on its way out (epic #375) the fader *is* the node's
    // grab handle in edit mode — this is the whole point of the mode.
    expect(slider.position, start + const Offset(30, 24));
    expect(sendFloats(), isEmpty);

    // ...and a marquee crosses it like any other node, which per-node press
    // arbitration could never allow.
    final canvasTL = tester.getTopLeft(find.byType(PatcherCanvas));
    g = await tester.startGesture(canvasTL + const Offset(6, 6));
    await tester.pump();
    await g.moveTo(canvasTL + const Offset(260, 320));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(patcher.graph.selectedNodes, contains(slider.id));

    // ── 2) Ctrl+E flips to run mode, from the key's *position* ──────────────
    // AZERTY-proof, exactly as `Ctrl+0` is (#369): the physical key in `E`'s
    // position, whatever glyph the layout reports for it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.keyJ,
      physicalKey: PhysicalKeyboardKey.keyE,
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.keyJ,
      physicalKey: PhysicalKeyboardKey.keyE,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(canvasMode(), PatchCanvasMode.run);
    // The mode is visible in the bar above the canvas, not just in behaviour.
    expect(find.text('RUN'), findsOneWidget);
    expect(find.text('EDIT'), findsNothing);
    // Selection is an editing state and goes with the mode.
    expect(patcher.graph.selectedNodes, isEmpty);

    // ── 3) run mode: the same press plays the fader; the node stays put ─────
    final placed = slider.position;
    patcherGateway.calls.clear();
    final track = tester.getRect(fader);
    g = await tester.startGesture(track.centerLeft + const Offset(14, 0));
    await tester.pump();
    // Up the track, so the value has to move somewhere it was not.
    await g.moveTo(Offset(track.center.dx, track.top + 8));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(sendFloats(), isNotEmpty);
    expect(slider.position, placed);
    expect(patcher.graph.selectedNodes, isEmpty);

    // Delete cannot take a node out of a patch that is being played, either.
    final nodeCount = patcher.graph.nodes.length;
    await tester.tapAt(canvasTL + const Offset(400, 400));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(patcher.graph.nodes, hasLength(nodeCount));

    // ── 4) the placement bar's toggle is the same switch ────────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(canvasMode(), PatchCanvasMode.edit);
    expect(find.text('EDIT'), findsOneWidget);

    // Back in edit mode the fader is a grab handle again.
    patcherGateway.calls.clear();
    g = await tester.startGesture(tester.getCenter(fader));
    await tester.pump();
    await g.moveBy(const Offset(0, -16));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(slider.position, placed + const Offset(0, -16));
    expect(sendFloats(), isEmpty);

    session.dispose();
    await engine.dispose();
  });
}
