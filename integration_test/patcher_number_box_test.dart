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
/// `guiValue` read-back; Backspace edits the text while a node stays selected
/// (it used to delete the selection); and once the canvas has focus back,
/// Delete removes the selection again.
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

    // ── 1) clicking the readout puts the caret in the field and leaves it ────
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    expect(box().focusNode!.hasPrimaryFocus, isTrue);
    // The press belonged to the body, so the node was not selected by it.
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

    // ── 3) Backspace edits the text, never the canvas selection ──────────────
    // Select the `~dac` first, so a wrongly-routed Backspace would be visible
    // as a deleted node.
    final nodesBefore = patcher.graph.nodes.length;
    await tester.tap(find.text('out · L/R'.toUpperCase()));
    await tester.pumpAndSettle();
    expect(patcher.graph.selectedNodes, hasLength(1));

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

    // Re-select the dac by clicking it, then Delete removes it as ever.
    await tester.tap(find.text('out · L/R'.toUpperCase()));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(patcher.graph.nodes, hasLength(nodesBefore - 1));

    session.dispose();
    await engine.dispose();
  });
}
