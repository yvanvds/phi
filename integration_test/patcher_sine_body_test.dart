import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/nodes/sine_node_body.dart';
import 'package:phi/surfaces/patcher/params/patch_params_dialog.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the `~sine` node prints its **real** frequency
/// (issue #354) through the real [PhiApp] — real rail navigation, real canvas
/// layout, real fonts — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched.
///
/// The body used to render a hardcoded `440`, so editing the frequency through
/// the params dialog changed what was sounding while the canvas kept lying. A
/// widget test cannot catch that regression on its own: the readout is only
/// refreshed because the composed canvas rebuilds the node from its own
/// listener when `setNodeParams` wakes it, and the dialog is reached by a real
/// double-click on the rendered header.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  /// The frequency the `~sine` node actually prints on the canvas.
  Finder freqReadout(String value) => find.descendant(
    of: find.byType(SineNodeBody),
    matching: find.text(value),
  );

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('the ~sine body prints its real frequency and follows the params '
      'dialog through undo/redo', (tester) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface, which seeds slider → sine → dac.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // The seeded node carries its documented default — and the body shows that
    // value because it read it, not because '440' is baked into the widget.
    final sine = engine.patcher.graph.nodes.firstWhere(
      (n) => n.type == Obj.dSine,
    );
    expect(engine.patcher.argsOf(sine.id), '440');
    expect(freqReadout('440'), findsOneWidget);

    // Double-click the `~sine` header to open the params dialog. Detected from
    // raw pointer timing, so two quick taps suffice.
    final header = find.text('osc · sine'.toUpperCase());
    final at = tester.getCenter(header);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(PatchParamsDialog.fieldKey('frequency')),
      '660',
    );
    await tester.tap(find.byKey(PatchParamsDialog.doneKey));
    await tester.pumpAndSettle();

    // The canvas follows the apply immediately — no reopen, no reload.
    expect(engine.patcher.argsOf(sine.id), '660');
    expect(freqReadout('660'), findsOneWidget);
    expect(freqReadout('440'), findsNothing);

    // ...and the display round-trips with the edit under Ctrl+Z / Ctrl+Y.
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(engine.patcher.argsOf(sine.id), '440');
    expect(freqReadout('440'), findsOneWidget);

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(engine.patcher.argsOf(sine.id), '660');
    expect(freqReadout('660'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
