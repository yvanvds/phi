import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
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

/// End-to-end proof that a `.f` number box is actually editable on the canvas
/// (issue #353), driven through the real [PhiApp] — real rail navigation, real
/// focus tree, real fonts and layout — backed by a [FakePatcherGateway] so no
/// native `libyse.dll` is touched.
///
/// A widget test can't see this class of bug: the failure lives in how the
/// composed surface arbitrates *focus* and *keys* between the canvas and the
/// field nested inside it. Only the full app has the shell's focus scopes, the
/// app-level `DefaultTextEditingShortcuts` and the canvas' own `Focus` stacked
/// in the order that produced the bug.
///
/// The four legs, in one session: clicking the readout takes the caret and
/// keeps it; typing + Enter pushes through `sendFloat` and shows the engine's
/// `guiValue` read-back; Backspace edits the text rather than reaching the
/// canvas behind it; and once the canvas has the keyboard back, Delete removes
/// a selected node again.
///
/// **Run mode is the premise** (issue #378). The object-box epic took the node
/// header away, so a GUI body that owned its own presses would leave a fader
/// unmovable and un-marquee-able; the canvas resolves that with a mode instead,
/// and in `edit` every body is switched off at the pointer. A number box is
/// therefore editable in `run` and inert in `edit` — deliberately — so this test
/// flips the mode the way a user does, from the placement bar above the canvas,
/// and flips back for the leg that deletes a node. The first press is spent
/// proving the inert half, since "the box does not take the caret in edit mode"
/// is now part of the contract rather than the bug this test was written for.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: a .f number box takes the caret, commits on Enter, '
      'and never hands its keys to the canvas', (tester) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface, which seeds slider → sine → dac and registers
    // the built-in node types.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // Drop a `.f` box onto the canvas — the same node the palette creates.
    final patcher = engine.patcher;
    // The seeded `~dac`, named by its own id: it is an object box now
    // (issue #379), printing exactly the `~dac` the palette also lists.
    final dacLine = find.byKey(
      PatcherNodeView.objectLineKey(
        patcher.graph.nodes.firstWhere((n) => n.type == Obj.dDac).id,
      ),
    );
    patcher.addNode(
      desc: NodeTypeRegistry.instance.find(Obj.gFloat)!,
      position: const Offset(140, 420),
    );
    await tester.pumpAndSettle();

    // Scoped to the node body: the surrounding surface has fields of its own.
    final field = find.descendant(
      of: find.byType(NumberNodeBody),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);
    TextField box() => tester.widget<TextField>(field);

    PatchCanvasMode mode() =>
        tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode;
    Future<void> flipMode() async {
      await tester.tap(find.byKey(PatchPlacementBar.modeKey));
      await tester.pumpAndSettle();
    }

    // ── 0) in edit mode the readout is inert, by design (issue #378) ─────────
    // The press goes to the canvas, which selects the node it landed on — the
    // body never sees it, so no caret lands in the field.
    expect(mode(), PatchCanvasMode.edit);
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    expect(box().focusNode!.hasPrimaryFocus, isFalse);
    expect(patcher.graph.selectedNodes, hasLength(1));

    // Play the patch, and the same pixels are a number box again.
    await flipMode();
    expect(mode(), PatchCanvasMode.run);

    // ── 1) clicking the readout puts the caret in the field and leaves it ────
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    expect(box().focusNode!.hasPrimaryFocus, isTrue);
    // The press belonged to the body, so the canvas started no gesture of its
    // own — and a run-mode canvas selects nothing in any case.
    expect(patcher.graph.selectedNodes, isEmpty);

    // ── 2) type a value and commit with Enter ────────────────────────────────
    await tester.enterText(field, '440');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      patcherGateway.calls.where((c) => c.endsWith(':0:440.000')),
      isNotEmpty,
    );
    // The box shows the value the engine reports back, not a Dart-side echo.
    expect(box().controller!.text, '440');

    // ── 3) Backspace edits the text, never the canvas behind it ──────────────
    // The canvas's own `Focus` is an *ancestor* of this field, so a Backspace
    // typed here reaches it first; it declines only because the field holds the
    // primary focus. Assert the node count with it, so a Backspace that leaked
    // through would show up as a deleted node rather than silently.
    final nodesBefore = patcher.graph.nodes.length;
    // Past the double-tap window first: the commit above left the field, and
    // the press that comes back to it is a fresh click, not the second half of
    // a pair on the same three characters.
    await tester.pump(kDoubleTapTimeout);
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    expect(box().focusNode!.hasPrimaryFocus, isTrue);

    await tester.enterText(field, '44');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(box().controller!.text, '4');
    expect(patcher.graph.nodes, hasLength(nodesBefore));

    // ── 4) Escape drops the edit; the canvas takes its keys back ─────────────
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(box().controller!.text, '440');

    // Back to editing the patch — deleting a node is an edit, and a patch being
    // played cannot be rearranged (issue #378).
    await flipMode();
    expect(mode(), PatchCanvasMode.edit);

    // Select the dac by clicking it, then Delete removes it as ever.
    await tester.tap(dacLine);
    await tester.pumpAndSettle();
    expect(patcher.graph.selectedNodes, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(patcher.graph.nodes, hasLength(nodesBefore - 1));

    session.dispose();
    await engine.dispose();
  });
}
