import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the patcher's grid discipline (issue #368) — the arrow
/// nudge and the snap-on-drop toggle — driven through the real [PhiApp]: real
/// rail navigation, real panes, the real focus tree, the real placement bar
/// above the canvas, backed by a [FakePatcherGateway] so no native `libyse.dll`
/// is touched.
///
/// A widget test cannot stand in for this one, because both legs are questions
/// about the *composition* rather than about the canvas in isolation:
///
/// - The nudge is a keyboard shortcut on a canvas buried under the shell's own
///   focus scopes and app-level shortcuts. Whether an arrow key reaches it at
///   all — instead of being eaten on the way down, or scrolling a pane — is
///   decided by the whole tree, and only the real one has all of it.
/// - The snap toggle lives in a *different widget* from the behaviour it
///   governs: it is chrome in the placement bar, and the canvas below only
///   snaps if the surface actually threads the flag from one to the other. A
///   canvas test that passes the flag by hand proves nothing about that wire.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: arrows nudge the selection as one undo step, and the '
      'snap toggle disciplines a drop', (tester) async {
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

    // Start from an empty canvas: the demo seed's nodes are not what this test
    // is about, and they would sit over the one that is.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    // One node of our own, near the scene origin so it is certainly on screen
    // whatever the panes around the canvas cost, and **on** the grid so the
    // snap leg below starts from a known cell.
    const start = Offset(48, 40);
    final sine = patcher.addNode(
      desc: NodeTypeRegistry.instance.find(Obj.dSine)!,
      position: start,
    );
    await tester.pumpAndSettle();

    final canvasTL = tester.getTopLeft(find.byType(PatcherCanvas));
    // The middle of the node's header — draggable chrome, and never a body that
    // runs its own gestures.
    Offset header() =>
        canvasTL +
        sine.position +
        Offset(sine.size.width / 2, PatchCanvasConstants.headerHeight / 2);

    // Click to select — which is also how the canvas comes to hold the
    // keyboard, exactly as it does for a real user.
    await tester.tapAt(header());
    await tester.pumpAndSettle();
    expect(patcher.graph.selectedNodes, {sine.id});

    // ── 1) a held arrow nudges on every repeat, and undoes as one step ───────
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sine.position, start + const Offset(48, 0));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(sine.position, start + const Offset(48, 0));

    // One Ctrl+Z takes the whole burst back — one command per repeat is what
    // would have made undo useless here.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sine.position, start);

    // Shift takes a major cell instead of a minor one.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(sine.position, start + const Offset(0, 64));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sine.position, start);

    // ── 2) snap off: a drop lands exactly where the pointer left it ──────────
    var drag = await tester.startGesture(header());
    await tester.pump();
    await drag.moveBy(const Offset(10, 10));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(sine.position, start + const Offset(10, 10));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sine.position, start);

    // ── 3) snap on: the same drop quantises to the grid ──────────────────────
    expect(find.byKey(PatchPlacementBar.snapKey), findsOneWidget);
    await tester.tap(find.byKey(PatchPlacementBar.snapKey));
    await tester.pumpAndSettle();

    patcherGateway.calls.clear();
    drag = await tester.startGesture(header());
    await tester.pump();
    await drag.moveBy(const Offset(10, 10));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    // (58, 50) rounded onto the 16px lattice the grid backdrop paints.
    expect(sine.position, const Offset(64, 48));
    // And the snapped position — not the raw one — is what reached the engine,
    // so a save round-trips the tidy layout.
    expect(
      patcherGateway.calls.where((c) => c.endsWith(':64.0:48.0')),
      isNotEmpty,
    );

    // Undo restores the origin the drag started from, grid or no grid.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(sine.position, start);

    // ── 4) with snap on, a nudge lands on the grid too ───────────────────────
    // Off-grid first, so the nudge has something to tidy up.
    patcher.placeNode(sine.id, const Offset(44, 60));
    await tester.pumpAndSettle();
    await tester.tapAt(header());
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sine.position, const Offset(60, 60));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(sine.position, const Offset(64, 64));

    session.dispose();
    await engine.dispose();
  });
}
