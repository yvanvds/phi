import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/params/patch_params_dialog.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the reworked patcher canvas (issue #222) through the real
/// [PhiApp] — real rail navigation, layout, fonts — backed by a
/// [FakePatcherGateway] (no native `libyse.dll`). Drives body drag, delete-with-
/// cables, and duplicate, each with undo, via real pointer + keyboard gestures.
///
/// Also the end-to-end guard for issue #352: in the composed app a node must
/// travel exactly as far as the pointer does — measured on the rendered header,
/// not just in the model — and a click-to-select immediately followed by a drag
/// must never be read as a double-click and open the params dialog.
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
    'patcher canvas: drag, delete-with-cables, duplicate — all undo',
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
      expect(find.byType(PatchNodeFrame), findsNWidgets(3));
      final graph = engine.patcher.graph;
      expect(graph.cables, hasLength(2));

      final canvasTopLeft = tester.getTopLeft(find.byType(PatcherCanvas));
      PatchNode nodeOfType(String type) =>
          graph.nodes.firstWhere((n) => n.type == type);

      // ── body drag (from the inert sine header) — moves and undoes ──────────
      final sine = nodeOfType(Obj.dSine);
      final sineStart = sine.position;
      final sineHeader = find.text('osc · sine'.toUpperCase());
      final drawnAtStart = tester.getTopLeft(sineHeader);
      final headerCentre = canvasTopLeft + sine.position + const Offset(65, 11);
      final drag = await tester.startGesture(headerCentre);
      await tester.pump();
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();
      await drag.moveBy(const Offset(40, 30));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      // Every pixel of the gesture reached the node — nothing was eaten by a
      // recogniser's slop — and the header is drawn where the pointer left it.
      expect(sine.position, sineStart + const Offset(80, 30));
      expect(
        tester.getTopLeft(sineHeader),
        drawnAtStart + const Offset(80, 30),
      );

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, sineStart);
      expect(tester.getTopLeft(sineHeader), drawnAtStart);

      // ── click to select, then drag straight away — the natural sequence that
      //    used to fire a double-click and open the params dialog instead ─────
      await tester.tapAt(headerCentre);
      await tester.pumpAndSettle();
      expect(graph.selectedNodes, {sine.id});

      final again = await tester.startGesture(headerCentre);
      await tester.pump();
      await again.moveBy(const Offset(35, 20));
      await tester.pump();
      await again.up();
      await tester.pumpAndSettle();

      expect(find.byType(PatchParamsDialog), findsNothing);
      expect(sine.position, sineStart + const Offset(35, 20));
      expect(
        tester.getTopLeft(sineHeader),
        drawnAtStart + const Offset(35, 20),
      );

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(sine.position, sineStart);

      // ── duplicate the dac (Ctrl+D) — copy appears, then undoes ─────────────
      await tester.tap(find.text('out · L/R'.toUpperCase()));
      await tester.pumpAndSettle();
      expect(graph.selectedNodes, {nodeOfType(Obj.dDac).id});

      await ctrl(tester, LogicalKeyboardKey.keyD);
      expect(find.byType(PatchNodeFrame), findsNWidgets(4));

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byType(PatchNodeFrame), findsNWidgets(3));

      // ── delete a node with its cable (Delete) — then undo restores both ────
      await tester.tap(find.text('out · L/R'.toUpperCase()));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.byType(PatchNodeFrame), findsNWidgets(2));
      expect(graph.cables, hasLength(1)); // sine → dac dropped with the node

      await ctrl(tester, LogicalKeyboardKey.keyZ);
      expect(find.byType(PatchNodeFrame), findsNWidgets(3));
      expect(graph.cables, hasLength(2));

      session.dispose();
      await engine.dispose();
    },
  );
}
