import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the reworked patcher canvas (issue #222) through the real
/// [PhiApp] — real rail navigation, layout, fonts — backed by a
/// [FakePatcherGateway] (no native `libyse.dll`). Drives body drag, delete-with-
/// cables, duplicate, and copy/paste (issue #435), each with undo, via real
/// pointer + keyboard gestures.
///
/// Also the end-to-end guard for issue #352: in the composed app a node must
/// travel exactly as far as the pointer does — measured on the rendered box,
/// not just in the model — and a click-to-select immediately followed by a drag
/// must never be read as a double-click and drop the object into its in-place
/// editor (issue #382).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'patcher canvas: drag, delete-with-cables, duplicate, copy/paste — '
    'all undo',
    (tester) async {
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

      // The seed lays down slider → sine → dac (3 nodes, 2 cables).
      expect(find.byType(PatcherNodeView), findsNWidgets(3));
      final graph = engine.patcher.graph;
      expect(graph.cables, hasLength(2));

      final canvasTopLeft = tester.getTopLeft(find.byType(PatcherCanvas));
      PatchNode nodeOfType(String type) =>
          graph.nodes.firstWhere((n) => n.type == type);

      // ── body drag — moves and undoes ──────────────────────────────────────
      // Aimed at the middle of the box, which since issue #379 is the whole
      // node: there is no header left to press.
      final sine = nodeOfType(Obj.dSine);
      final sineStart = sine.position;
      // Named by the node's own id: the palette lists a `~dac` entry too, and
      // an object box prints exactly the type id the palette does (issue #379).
      final sineLine = find.byKey(PatcherNodeView.objectLineKey(sine.id));
      final dacLine = find.byKey(
        PatcherNodeView.objectLineKey(nodeOfType(Obj.dDac).id),
      );
      final drawnAtStart = tester.getTopLeft(sineLine);
      final headerCentre =
          canvasTopLeft +
          sine.position +
          Offset(sine.size.width / 2, sine.size.height / 2);
      final drag = await tester.startGesture(headerCentre);
      await tester.pump();
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();
      await drag.moveBy(const Offset(40, 30));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      // Every pixel of the gesture reached the node — nothing was eaten by a
      // recogniser's slop — and the box is drawn where the pointer left it.
      expect(sine.position, sineStart + const Offset(80, 30));
      expect(tester.getTopLeft(sineLine), drawnAtStart + const Offset(80, 30));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, sineStart);
      expect(tester.getTopLeft(sineLine), drawnAtStart);

      // ── click to select, then drag straight away — the natural sequence that
      //    used to fire a double-click and open the editor instead ────────────
      await tester.tapAt(headerCentre);
      await tester.pumpAndSettle();
      expect(graph.selectedNodes, {sine.id});

      final again = await tester.startGesture(headerCentre);
      await tester.pump();
      await again.moveBy(const Offset(35, 20));
      await tester.pump();
      await again.up();
      await tester.pumpAndSettle();

      expect(find.byKey(PatcherCanvas.inlineEditKey), findsNothing);
      expect(sine.position, sineStart + const Offset(35, 20));
      expect(tester.getTopLeft(sineLine), drawnAtStart + const Offset(35, 20));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, sineStart);

      // ── duplicate the dac (Ctrl+D) — copy appears, then undoes ─────────────
      await tester.tap(dacLine);
      await tester.pumpAndSettle();
      expect(graph.selectedNodes, {nodeOfType(Obj.dDac).id});

      await ctrl(tester, LogicalKeyboardKey.keyD);
      expect(find.byType(PatcherNodeView), findsNWidgets(4));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byType(PatcherNodeView), findsNWidgets(3));

      // ── delete a node with its cable (Delete) — then undo restores both ────
      // Re-select the dac by way of another node: two clicks on the *same* box
      // pair into a double-click, and since issue #382 that opens the box for
      // typing — which would take the keyboard this Delete needs.
      await tester.tap(sineLine);
      await tester.pumpAndSettle();
      await tester.tap(dacLine);
      await tester.pumpAndSettle();
      expect(find.byKey(PatcherCanvas.inlineEditKey), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(PatcherNodeView), findsNWidgets(2));
      expect(graph.cables, hasLength(1)); // sine → dac dropped with the node

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byType(PatcherNodeView), findsNWidgets(3));
      expect(graph.cables, hasLength(2));

      // ── copy the dac (Ctrl+C), paste it (Ctrl+V) — the copy appears offset,
      //    selected, and undoes as one step (issue #435) ──────────────────────
      // Select by way of another node, for the same double-click reason above.
      await tester.tap(sineLine);
      await tester.pumpAndSettle();
      await tester.tap(dacLine);
      await tester.pumpAndSettle();
      final dac = nodeOfType(Obj.dDac);
      expect(graph.selectedNodes, {dac.id});

      await ctrl(tester, LogicalKeyboardKey.keyC);
      // Copying is not an edit — nothing appeared yet.
      expect(find.byType(PatcherNodeView), findsNWidgets(3));

      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(find.byType(PatcherNodeView), findsNWidgets(4));
      final pasted = graph.nodes.firstWhere(
        (n) => n.type == Obj.dDac && n.id != dac.id,
      );
      // One grid step down-right of the original, and now the selection —
      // ready to drag into place.
      expect(pasted.position, dac.position + const Offset(16, 16));
      expect(graph.selectedNodes, {pasted.id});

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byType(PatcherNodeView), findsNWidgets(3));

      session.dispose();
      await engine.dispose();
    },
  );
}
