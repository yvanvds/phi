import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/nodes/number_node_body.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the patcher's view navigation (issue #369) — the
/// space-hold pan and the `Ctrl+0` frame — driven through the real [PhiApp]:
/// real rail navigation, real panes, the real focus tree, a real mouse cursor
/// resolved by the framework's own tracker, backed by a [FakePatcherGateway] so
/// no native `libyse.dll` is touched.
///
/// A widget test cannot stand in for this one, because every leg is a question
/// about the *composition* rather than about the canvas in isolation:
///
/// - Whether a bare `Space` reaches the canvas at all is decided by the whole
///   tree above it. It is the one key every `Shortcuts` map, every focusable
///   button and every scrollable in the shell has an opinion about — a canvas
///   test has none of them, and so cannot tell that the key was not eaten on
///   the way down or read as "activate the focused thing".
/// - The grab cursor is resolved by the framework's mouse tracker against the
///   whole hit-test path, so every `MouseRegion` the shell wraps the surface in
///   gets a vote; only the real stack has them.
/// - The frame is measured against the *real* viewport the canvas was given
///   once the rail, the palette and the reference panel have taken their share
///   — a number a canvas pumped on its own can only invent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: space-hold pans the view and Ctrl+0 frames the patch', (
    tester,
  ) async {
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

    // Start from an empty canvas: the demo seed's nodes are not what this test
    // is about, and they would sit over the ones that are.
    final patcher = engine.patcher;
    for (final id in patcher.graph.nodes.map((n) => n.id).toList()) {
      patcher.removeNode(id);
    }
    await tester.pumpAndSettle();

    // Two nodes of our own near the scene origin, so they are certainly on
    // screen whatever the panes around the canvas cost. The `.f` box is there
    // for the focus leg — it is the widget that takes the keyboard away.
    final registry = NodeTypeRegistry.instance;
    final number = patcher.addNode(
      desc: registry.find(Obj.gFloat)!,
      position: const Offset(60, 40),
    );
    final sine = patcher.addNode(
      desc: registry.find(Obj.dSine)!,
      position: const Offset(280, 180),
    );
    await tester.pumpAndSettle();

    final canvas = tester.getRect(find.byType(PatcherCanvas));

    /// The rectangle the drawn nodes actually occupy on screen, taken from the
    /// real render objects rather than from the model — the point of framing is
    /// where things *land*, and only the layout knows that.
    Rect drawn() {
      Rect? r;
      for (final e in find.byType(PatchNodeFrame).evaluate()) {
        final box = e.renderObject! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        r = r == null ? rect : r.expandToInclude(rect);
      }
      return r!;
    }

    bool framed(Rect r) =>
        r.left >= canvas.left - 0.5 &&
        r.top >= canvas.top - 0.5 &&
        r.right <= canvas.right + 0.5 &&
        r.bottom <= canvas.bottom + 0.5;

    double panX() => patcher.transform.value.getTranslation().x;
    double panY() => patcher.transform.value.getTranslation().y;

    /// A point on empty canvas, far from both nodes.
    final empty = canvas.bottomRight - const Offset(60, 60);

    // A parked mouse, so the cursor is resolved the way a real one resolves it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await tester.pumpAndSettle();

    // ── 1) space held, a left-drag pans — and says so with the cursor ────────
    await mouse.moveTo(empty);
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    // A click on empty canvas is how the canvas comes to hold the keyboard,
    // exactly as it does for a real user.
    await mouse.down(empty);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grab,
      reason: 'a bare Space must reach the canvas through the whole shell',
    );

    await mouse.down(empty);
    await tester.pumpAndSettle();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.grabbing,
    );

    await mouse.moveBy(const Offset(-40, -30));
    await tester.pump();
    expect(panX(), -40);
    expect(panY(), -30);
    // A pan is not a selection gesture: nothing was marqueed on the way.
    expect(find.byKey(PatcherCanvas.marqueeKey), findsNothing);
    expect(patcher.graph.selectedNodes, isEmpty);

    await mouse.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(panX(), -40);
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    // ── 1b) letting go mid-drag ends the pan, wherever the key-up landed ─────
    //
    // The one leg that only the real shell can pose: the enclosing pane grabs
    // the keyboard on every pointer-down, so the release of a space held
    // *through* a drag never reaches the canvas as a key event at all. The pan
    // still has to stop with the key.
    patcher.transform.value = Matrix4.identity();
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    final held = await tester.startGesture(empty);
    await tester.pump();
    await held.moveBy(const Offset(-30, -20));
    await tester.pump();
    expect(panX(), -30);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await held.moveBy(const Offset(-60, -60));
    await tester.pump();
    expect(panX(), -30);
    expect(panY(), -20);

    await held.up();
    await tester.pumpAndSettle();

    // ── 2) without space the same drag still marquees ────────────────────────
    patcher.transform.value = Matrix4.identity();
    await tester.pumpAndSettle();

    final marquee = await tester.startGesture(
      canvas.topLeft + const Offset(8, 8),
    );
    await tester.pump();
    await marquee.moveTo(canvas.topLeft + const Offset(420, 300));
    await tester.pump();
    expect(find.byKey(PatcherCanvas.marqueeKey), findsOneWidget);
    await marquee.up();
    await tester.pumpAndSettle();

    expect(patcher.graph.selectedNodes, contains(number.id));
    expect(panX(), 0);
    expect(panY(), 0);

    // ── 3) space while the `.f` box holds the keyboard never pans ────────────
    // Scoped to the node body: the shell has search fields of its own.
    final field = find.descendant(
      of: find.byType(NumberNodeBody),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    final typing = await tester.startGesture(empty);
    await tester.pump();
    await typing.moveBy(const Offset(-40, -30));
    await tester.pump();
    await typing.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    // The space belonged to the field being typed into (issue #353): the view
    // never moved.
    expect(panX(), 0);
    expect(panY(), 0);

    // ── 4) Ctrl+0 frames the patch from wherever the view has wandered ───────
    expect(framed(drawn()), isTrue);

    // Lost: panned right off the patch, at a zoom that shows none of it.
    patcher.transform.value = Matrix4.identity()
      ..translateByDouble(-2400, -1800, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pumpAndSettle();
    expect(framed(drawn()), isFalse);

    // Take the keyboard back the way a user would, then ask for the patch.
    await tester.tapAt(empty);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      framed(drawn()),
      isTrue,
      reason: 'Ctrl+0 must fit the graph into the viewport it was really given',
    );
    // Both nodes came back, not just the one nearest the origin.
    expect(find.byType(PatchNodeFrame), findsNWidgets(2));
    expect(patcher.graph.nodeById(sine.id), isNotNull);

    // ── 5) the wheel zooms, and the zoom-out floor really bites (#373) ───────
    //
    // A composition question rather than a canvas one: a pointer *signal* is
    // offered to every scrollable on the hit-test path before the canvas sees
    // it, and the patcher sits inside panes, a palette list and a reference
    // panel that all have one. Only the real stack can say the notch arrived —
    // and only the real render tree can say how big the patch is left drawn,
    // which is the whole complaint in the issue.
    patcher.transform.value = Matrix4.identity();
    await tester.pumpAndSettle();

    /// Where each drawn node's corner sits on screen.
    List<Offset> corners() => [
      for (final e in find.byType(PatchNodeFrame).evaluate())
        (e.renderObject! as RenderBox).localToGlobal(Offset.zero),
    ];

    /// The on-screen distance between the two nodes — the one measure that
    /// scales *exactly* with the view, since a frame's own box is laid out at
    /// its model size and only the transform above it shrinks.
    double spread() {
      final c = corners();
      return (c[1] - c[0]).distance;
    }

    final unzoomed = spread();

    /// The view's zoom off the x basis — never `getMaxScaleOnAxis`, which
    /// reports 1.0 for every zoomed-out 2-D view and is the bug itself.
    double zoom() => patcher.transform.value.entry(0, 0);

    final wheel = TestPointer(9, PointerDeviceKind.mouse);
    wheel.hover(empty);
    Future<void> notch(double dy, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.sendEventToBinding(wheel.scroll(Offset(0, dy)));
        await tester.pump();
      }
    }

    await notch(-100);
    expect(
      zoom(),
      closeTo(1.1, 1e-9),
      reason: 'a wheel notch must reach the canvas through the whole shell',
    );

    // Far past the 15 notches that reach the floor from 1:1.
    await notch(100, times: 40);
    expect(zoom(), closeTo(0.25, 1e-9));

    // The patch is still a patch — a quarter size, not wheeled away to a dot.
    expect(spread(), closeTo(unzoomed * 0.25, 0.5));
    // And still on screen, at the size a quarter zoom leaves it.
    expect(find.byType(PatchNodeFrame), findsNWidgets(2));
    for (final c in corners()) {
      expect(canvas.contains(c), isTrue);
    }

    // And the way back is stepped from where the view really is.
    await notch(-100, times: 3);
    expect(zoom(), closeTo(0.25 * 1.1 * 1.1 * 1.1, 1e-9));

    session.dispose();
    await engine.dispose();
  });
}
