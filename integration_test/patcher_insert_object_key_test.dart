import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_object_types.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the insert-object key (issue #468): **hover the grid →
/// press `N` → type a name → Enter → the object is there**, driven through the
/// real [PhiApp] — real rail navigation, real shell focus scopes and shortcut
/// maps — backed by a [FakePatcherGateway] so no native engine is touched.
///
/// The composition is the risk a widget test cannot see: a plain letter has to
/// get past every shortcut map the shell stacks above the canvas and reach the
/// canvas' own `Focus`, after the workstation pane has grabbed the keyboard on
/// the click that focused it; and the box it opens has to take the keyboard so
/// the name is typed, not run as canvas shortcuts.
///
/// The legs, in one session: `N` opens the box under the pointer and Enter
/// makes the typed `~sine` there; run mode declines `N`; and with the pointer
/// gone from the canvas the box opens at the viewport centre.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: N opens the object box under the pointer, and the '
      'typed object is made there', (tester) async {
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: FakePatcherGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface, which seeds slider → sine → dac.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    final patcher = engine.patcher;
    final seeded = patcher.graph.nodes.length;

    final canvas = find.byType(PatcherCanvas);
    final canvasRect = tester.getRect(canvas);
    // Empty grid, clear of the seeded chain (which sits above scene y≈310).
    const scenePoint = Offset(220, 380);
    final at = canvasRect.topLeft + scenePoint;
    expect(canvasRect.contains(at), isTrue);

    Finder box() => find.byKey(PatcherCanvas.inlineCreateKey);
    Finder field() => find.byKey(PatchInlineObjectBox.fieldKey);

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    // A real mouse: it hovers, and a click on the grid hands the canvas the
    // keyboard through the pane's own pointer-down focus grab.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    await tester.pump();
    await mouse.moveTo(at);
    await tester.pump();
    await mouse.down(at);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    // ── 1) N opens the box under the pointer, holding the keyboard ───────────
    expect(box(), findsNothing);
    await press(LogicalKeyboardKey.keyN);

    expect(box(), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PatchInlineObjectBox)), at);
    expect(
      tester.widget<TextField>(field()).focusNode!.hasPrimaryFocus,
      isTrue,
    );

    // ── 2) type, Enter: the object is made where the pointer was ─────────────
    await tester.enterText(field(), 'sine 220');
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.enter);

    expect(box(), findsNothing);
    expect(patcher.graph.nodes, hasLength(seeded + 1));
    final made = patcher.graph.nodes.last;
    expect(made.type, PatchObjectTypes.dSine);
    expect(patcher.argsOf(made.id), '220');
    expect(made.position, scenePoint);

    // ── 3) run mode declines N ───────────────────────────────────────────────
    await ctrl(LogicalKeyboardKey.keyE);
    await press(LogicalKeyboardKey.keyN);
    expect(box(), findsNothing);
    await ctrl(LogicalKeyboardKey.keyE);

    // ── 4) with the pointer off the canvas, the box opens mid-viewport ───────
    await mouse.moveTo(canvasRect.topLeft - const Offset(4, 4));
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.keyN);

    expect(box(), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(PatchInlineObjectBox)),
      canvasRect.center,
    );
    await press(LogicalKeyboardKey.escape);
    expect(box(), findsNothing);
    expect(patcher.graph.nodes, hasLength(seeded + 1));

    await mouse.removePointer();
    session.dispose();
    await engine.dispose();
  });
}
