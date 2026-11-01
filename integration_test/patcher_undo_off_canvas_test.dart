import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_object_types.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the patch's undo is reachable from anywhere in the
/// patcher's pane (issue #512), driven through the real [PhiApp].
///
/// The bug lived entirely in the composition: the pane takes the keyboard on
/// any press inside it, so a click in the palette or the reference panel left
/// the canvas — the only thing that routed Ctrl+Z to the patch — without focus,
/// and the shell's own `edit.undo` had no patcher stack to act on. Only the real
/// shell has the pane's focus grab, the app-level shortcuts and the undo router
/// together, so a canvas widget test cannot see it.
///
/// Also pinned here: with the canvas focused, one Ctrl+Z is still exactly one
/// undo step (the canvas and the shell must not both act on it), and run mode
/// still declines undo however the chord arrives.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: Ctrl+Z undoes a move after a click in the palette or '
      'the reference panel', (tester) async {
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

    final patcher = engine.patcher;
    expect(patcher.graph.nodes, isEmpty, reason: 'a new patch opens empty');
    // One node of our own, near the origin so it is on screen whatever the
    // side panels cost.
    const start = Offset(48, 40);
    final sine = patcher.addNode(
      desc: NodeTypeRegistry.instance.find(PatchObjectTypes.dSine)!,
      position: start,
    );
    await tester.pumpAndSettle();

    final canvasTL = tester.getTopLeft(find.byType(PatcherCanvas));
    Offset middle() =>
        canvasTL +
        sine.position +
        Offset(sine.size.width / 2, sine.size.height / 2);

    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<void> move(Offset by) async {
      await tester.dragFrom(middle(), by);
      await tester.pumpAndSettle();
    }

    final paletteEntry = find.byKey(
      PatcherPalette.entryKey(PatchObjectTypes.dSine),
    );

    // ── 1) move, click a palette entry, Ctrl+Z → the move is undone ──────────
    await move(const Offset(80, 40));
    final moved = sine.position;
    expect(moved, isNot(start));
    await tester.tap(paletteEntry);
    await tester.pumpAndSettle();
    // The palette tap documented the type — and took the keyboard off the
    // canvas, which is the repro's whole precondition.
    expect(find.byKey(PatchReferencePanel.emptyKey), findsNothing);
    expect(
      tester
          .widget<PatcherCanvas>(find.byType(PatcherCanvas))
          .focusNode
          ?.hasFocus,
      isFalse,
    );
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, start);

    // Ctrl+Y from the same place redoes it.
    await ctrl(LogicalKeyboardKey.keyY);
    expect(sine.position, moved);
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, start);

    // ── 2) the same after a click anywhere in the reference panel ────────────
    await move(const Offset(60, 20));
    expect(sine.position, isNot(start));
    await tester.tap(find.byType(PatchReferencePanel));
    await tester.pumpAndSettle();
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, start);

    // ── 3) canvas focused: one Ctrl+Z is one step, not two ───────────────────
    await move(const Offset(40, 0));
    final first = sine.position;
    await move(const Offset(0, 40));
    expect(sine.position, isNot(first));
    // The drag left the canvas holding the keyboard.
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, first);
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, start);

    // ── 4) run mode declines undo, from the canvas or from the pane ──────────
    await move(const Offset(40, 40));
    final beforeRun = sine.position;
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    await tester.tap(paletteEntry);
    await tester.pumpAndSettle();
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, beforeRun);

    // Back in edit mode the stack is reachable again, untouched.
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    await tester.tap(paletteEntry);
    await tester.pumpAndSettle();
    await ctrl(LogicalKeyboardKey.keyZ);
    expect(sine.position, start);

    session.dispose();
    await engine.dispose();
  });
}
