import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/fader/phi_fader.dart';
import 'package:phi/design/widgets/patcher/patch_bang_square.dart';
import 'package:phi/design/widgets/patcher/patch_gui_object.dart';
import 'package:phi/design/widgets/patcher/patch_message_box.dart';
import 'package:phi/design/widgets/patcher/patch_number_box.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/design/widgets/patcher/patch_toggle_square.dart';
import 'package:phi/domain/patcher/patch_node.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/engine/state/node_type_registry.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patch_canvas_mode.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/placement/patch_placement_bar.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of **GUI objects as bare controls** (issue #381, design §7,
/// §12.2) through the real [PhiApp] — real rail navigation, real canvas layout,
/// real fonts — backed by a [FakePatcherGateway] so no native `libyse.dll` is
/// touched.
///
/// A bang was a `BUTTON` header over a 40px square captioned `bang` inside a
/// 90×90 frame; a toggle a `TOGGLE` header over a pill; a slider a `SLIDER`
/// header over a fader and a readout. Each is now only itself.
///
/// A widget test structurally cannot stand in for this one:
///
/// - "No caption anywhere on the node" is a claim about the *composed* node —
///   the view, the seat, and the body it builds out of the registry. A widget
///   test that pumps one body in isolation cannot see the chrome that used to
///   wrap it, because it never had it.
/// - The controls are laid out to their node's rectangle, which the controller
///   sizes from the registry and floors against the port geometry. Only the real
///   canvas puts those two together — and only the real font tells whether the
///   number box's one-line height actually holds a real readout without
///   overflowing.
/// - Dragging a headerless node from anywhere on itself is arbitration between
///   the canvas's pointer pipeline and a live body, settled by widgets at three
///   depths of the real tree (issue #378).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: bang, toggle, slider, number and message sit on the '
      'canvas as five bare controls', (tester) async {
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

    /// Add one of the built-in GUI types at [position] — through the registry
    /// the palette drops from, so the node is sized exactly as a dropped one.
    PatchNode gui(String type, Offset position) => patcher.addNode(
      desc: NodeTypeRegistry.instance.find(type)!,
      position: position,
    );

    // The seeded `.slider` first, moved near the scene origin so the whole row
    // is certainly on screen whatever the strip and panels around it cost.
    final slider = patcher.graph.nodes.firstWhere((n) => n.type == Obj.gSlider);
    patcher.placeNode(slider.id, const Offset(30, 30));
    final bang = gui(Obj.gButton, const Offset(110, 30));
    final toggle = gui(Obj.gToggle, const Offset(170, 30));
    final number = gui(Obj.gFloat, const Offset(230, 30));
    final message = gui(Obj.gMessage, const Offset(320, 30));
    await tester.pumpAndSettle();

    // ─── (1) five controls, and not one caption between them ───────────────
    expect(find.byType(PhiFader), findsOneWidget);
    expect(find.byType(PatchBangSquare), findsOneWidget);
    expect(find.byType(PatchToggleSquare), findsOneWidget);
    expect(find.byType(PatchNumberBox), findsOneWidget);
    expect(find.byType(PatchMessageBox), findsOneWidget);
    // Each is seated bare — five GUI objects, no frame among them.
    expect(find.byType(PatchGuiObject), findsNWidgets(5));

    // The headers that used to name them are gone, and so is the `bang` caption
    // that sat inside the button. What text is left on these five nodes is the
    // *content* of the two boxes — a value and a message — and nothing else.
    for (final gone in ['BUTTON', 'TOGGLE', 'SLIDER', 'MESSAGE', 'bang']) {
      expect(find.text(gone), findsNothing, reason: '$gone is a caption');
    }
    expect(find.text('number · f'.toUpperCase()), findsNothing);

    // ─── (2) each control fills its own node, edge to edge ─────────────────
    // No frame, no header band, no body padding taking a bite out of it.
    void fillsItsNode(PatchNode node, Finder control) {
      expect(
        tester.getSize(control),
        node.size,
        reason: '${node.type} should fill its rectangle',
      );
    }

    fillsItsNode(bang, find.byType(PatchBangSquare));
    fillsItsNode(toggle, find.byType(PatchToggleSquare));
    fillsItsNode(number, find.byType(PatchNumberBox));
    fillsItsNode(message, find.byType(PatchMessageBox));

    // ─── (3) …and those rectangles shrank to Max-like sizes ────────────────
    // The bang was 90×90, the toggle 90×80, the number 110×70, the message
    // 120×66. Taking visibly less canvas is the epic's headline claim.
    expect(bang.size.width, lessThan(90));
    expect(bang.size.height, lessThan(90));
    expect(toggle.size.height, lessThan(80));
    expect(number.size.height, lessThan(70));
    expect(message.size.height, lessThan(66));
    // The one-line boxes are exactly one line tall — the same line an object
    // box spends, so a row of mixed nodes sits on one baseline.
    final sineBox = tester.getSize(
      find.ancestor(
        of: find.text('sine 440'),
        matching: find.byType(PatchObjectBox),
      ),
    );
    expect(number.size.height, sineBox.height);
    expect(message.size.height, sineBox.height);

    // ...and the real font actually fits in it: an overflowing readout would
    // have thrown by now.
    expect(tester.takeException(), isNull);

    // ─── (4) run mode: every control still operates its native object ──────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatcherCanvas>(find.byType(PatcherCanvas)).mode,
      PatchCanvasMode.run,
    );

    List<String> callsLike(String prefix) =>
        patcherGateway.calls.where((c) => c.startsWith(prefix)).toList();

    patcherGateway.calls.clear();
    await tester.tap(find.byType(PatchBangSquare));
    await tester.pumpAndSettle();
    expect(callsLike('sendBang'), isNotEmpty);

    patcherGateway.calls.clear();
    await tester.tap(find.byType(PatchToggleSquare));
    await tester.pumpAndSettle();
    expect(callsLike('sendFloat').single, endsWith(':0:1.000'));
    // ...and the switch shows it, with its cross rather than with a caption.
    expect(
      tester.widget<PatchToggleSquare>(find.byType(PatchToggleSquare)).value,
      isTrue,
    );

    patcherGateway.calls.clear();
    await tester.tap(find.byType(PatchMessageBox));
    await tester.pumpAndSettle();
    expect(callsLike('sendBang'), isNotEmpty);

    patcherGateway.calls.clear();
    final readout = find.descendant(
      of: find.byType(PatchNumberBox),
      matching: find.byType(TextField),
    );
    await tester.enterText(readout, '2.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(callsLike('sendFloat').last, endsWith(':0:2.500'));

    // ─── (5) a value arriving from the graph still moves the control ───────
    final toggleHandle = patcherGateway.nodes.entries
        .firstWhere((e) => e.value.type == Obj.gToggle)
        .key;
    patcherGateway.nodes[toggleHandle]!.guiValue = '0';
    patcher.refreshGuiValues();
    await tester.pumpAndSettle();
    expect(
      tester.widget<PatchToggleSquare>(find.byType(PatchToggleSquare)).value,
      isFalse,
    );

    // ─── (6) edit mode: each control is its own grab handle ────────────────
    await tester.tap(find.byKey(PatchPlacementBar.modeKey));
    await tester.pumpAndSettle();

    patcherGateway.calls.clear();
    final before = bang.position;
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PatchBangSquare)),
    );
    await tester.pump();
    await g.moveBy(const Offset(18, 26));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    // Dragged from the middle of the square itself — there is no chrome left to
    // aim at, which is exactly why the mode exists (issue #378).
    expect(bang.position, before + const Offset(18, 26));
    expect(callsLike('sendBang'), isEmpty);

    session.dispose();
    await engine.dispose();
  });
}
