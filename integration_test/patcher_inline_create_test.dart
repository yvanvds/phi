import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/create/patch_inline_object_box.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the Max speed path (issue #358): **double-click empty
/// canvas → type a name and arguments → Enter → the object is there**, driven
/// through the real [PhiApp] — real rail navigation, real focus tree, real
/// fonts and layout — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched.
///
/// A widget test cannot stand in for this one. The gesture's whole risk lives
/// in *composition*: the double-click has to survive the surrounding pane's
/// pointer-down focus grab, the typed keys have to reach a field nested inside
/// a canvas that owns Delete / Ctrl+D / Ctrl+Z, Tab must not be eaten by the
/// app's traversal, and Ctrl+Z afterwards has to find the patcher's undo scope
/// through the shell's focus-following undo. Only the assembled app has the
/// shell focus scopes, `DefaultTextEditingShortcuts` and the canvas' own
/// `Focus` stacked in the order that can break it.
///
/// The legs, in one session: the box opens where the grid was double-clicked;
/// completion narrows as the name is typed; Enter instantiates a `~sine` with
/// the typed argument at that exact point; Ctrl+Z un-creates it; an unknown
/// name is refused without costing the gesture; and Escape leaves the canvas
/// exactly as it was.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: an object is made by keyboard alone — double-click, '
      'type, Enter — and Ctrl+Z takes it back', (tester) async {
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

    // A patch of empty grid, well clear of the seeded chain (which all sits
    // above scene y≈310).
    final canvasRect = tester.getRect(find.byType(PatcherCanvas));
    const scenePoint = Offset(220, 380);
    final at = canvasRect.topLeft + scenePoint;
    expect(
      canvasRect.contains(at),
      isTrue,
      reason:
          'the canvas must be big enough to hold empty grid below the '
          'seeded chain — otherwise this test is clicking on nothing',
    );

    Finder box() => find.byKey(PatcherCanvas.inlineCreateKey);
    Finder field() => find.byKey(PatchInlineObjectBox.fieldKey);

    Future<void> doubleClick() async {
      await tester.tapAt(at);
      await tester.pump();
      await tester.tapAt(at);
      await tester.pumpAndSettle();
    }

    Future<void> type(String text) async {
      await tester.enterText(field(), text);
      await tester.pumpAndSettle();
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Future<void> ctrlZ() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    // ── 1) double-clicking the grid drops an object box right there ──────────
    expect(box(), findsNothing);
    await doubleClick();

    expect(box(), findsOneWidget);
    expect(tester.getTopLeft(find.byType(PatchInlineObjectBox)), at);
    // It opened focused: the next keystroke is already going into it, which is
    // the entire reason this path exists.
    expect(
      tester.widget<TextField>(field()).focusNode!.hasPrimaryFocus,
      isTrue,
    );

    // ── 2) the name narrows the catalogue as it is typed ─────────────────────
    await type('s');
    expect(find.byKey(PatchInlineObjectBox.rowKey(Obj.dSine)), findsOneWidget);
    expect(
      find.byKey(PatchInlineObjectBox.rowKey(Obj.gSlider)),
      findsOneWidget,
    );
    expect(find.byKey(PatchInlineObjectBox.rowKey(Obj.dDac)), findsNothing);

    await type('sine');
    expect(find.byKey(PatchInlineObjectBox.rowKey(Obj.dSine)), findsOneWidget);
    expect(find.byKey(PatchInlineObjectBox.rowKey(Obj.gSlider)), findsNothing);

    // ── 3) Enter instantiates it, with the typed creation argument ───────────
    await type('sine 220');
    await press(LogicalKeyboardKey.enter);

    expect(box(), findsNothing);
    expect(patcher.graph.nodes, hasLength(seeded + 1));
    final made = patcher.graph.nodes.last;
    expect(made.type, Obj.dSine);
    // `~sine` was never typed in full, and the `220` landed as its creation
    // argument — not the documented default of 440.
    expect(patcher.argsOf(made.id), '220');
    // And it sits exactly where the grid was double-clicked.
    expect(made.position, scenePoint);
    // The fresh object is the selection, so the hand that typed it can go
    // straight on to move or delete it.
    expect(patcher.graph.selectedNodes, {made.id});

    // ── 4) Ctrl+Z un-creates it, with no click in between ────────────────────
    await ctrlZ();
    expect(patcher.graph.nodes, hasLength(seeded));
    expect(patcher.graph.nodeById(made.id), isNull);

    // ── 5) an unknown name is refused inline, and the box stays open ─────────
    await doubleClick();
    await type('zzzz');
    await press(LogicalKeyboardKey.enter);

    expect(patcher.graph.nodes, hasLength(seeded));
    expect(box(), findsOneWidget);
    expect(find.byKey(PatchInlineObjectBox.rejectKey), findsOneWidget);

    // Corrected in place — the typo cost a keystroke, not the gesture.
    await type('slider');
    await press(LogicalKeyboardKey.enter);
    expect(patcher.graph.nodes, hasLength(seeded + 1));
    expect(patcher.graph.nodes.last.type, Obj.gSlider);
    await ctrlZ();
    expect(patcher.graph.nodes, hasLength(seeded));

    // ── 6) Escape leaves the canvas exactly as it was ────────────────────────
    await doubleClick();
    await type('sine 220');
    await press(LogicalKeyboardKey.escape);

    expect(box(), findsNothing);
    expect(patcher.graph.nodes, hasLength(seeded));

    session.dispose();
    await engine.dispose();
  });
}
