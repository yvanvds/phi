import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_canvas_constants.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/design/widgets/patcher/patch_object_box.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/params/patch_params_dialog.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof of the **object box** (issue #379, design §7/§12.2) through
/// the real [PhiApp] — real rail navigation, real canvas layout, **real fonts**
/// — backed by a [FakePatcherGateway] so no native `libyse.dll` is touched.
///
/// An engine object used to be a 22px uppercase header (`OSC · SINE`) over a
/// body printing roughly the same thing again with its arguments (`~sine 440`):
/// two rows and ~70px of canvas for one line's worth of information. Now the
/// box *is* the object — one bordered line, sized to its own text.
///
/// A widget test structurally cannot stand in for this. The box's width is
/// **measured** from the line it prints, so it is only right if the font the
/// real app lays out with is the font the measurement used — a test font would
/// happily agree with itself and prove nothing. And the re-measure on a params
/// edit only lands because the composed canvas rebuilds the node from its own
/// listener when `setNodeParams` wakes it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  /// The object box printing exactly [line].
  Finder boxFor(String line) =>
      find.ancestor(of: find.text(line), matching: find.byType(PatchObjectBox));

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('engine objects render as one bordered line sized to their text, '
      'and re-measure when their arguments change', (tester) async {
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

    // ─── (1) one line, and the title is gone ──────────────────────────────
    expect(boxFor('sine 440'), findsOneWidget);
    expect(boxFor('dac'), findsOneWidget);
    // Not `OUT · L/R` over an empty body, and not `OSC · SINE` over the line
    // that already says it.
    expect(find.text('osc · sine'.toUpperCase()), findsNothing);
    expect(find.text('out · L/R'.toUpperCase()), findsNothing);
    // The `.slider` keeps its frame until issue #381 — so the frames that are
    // left are GUI objects only, never an engine object.
    expect(find.byType(PatchNodeFrame), findsOneWidget);

    final sineSize = tester.getSize(boxFor('sine 440'));
    final dacSize = tester.getSize(boxFor('dac'));

    // One text line plus padding — half of the ~70px two-row node it replaces,
    // which is what makes a patch of these take visibly less canvas.
    expect(sineSize.height, lessThan(2 * PatchCanvasConstants.headerHeight));
    expect(dacSize.height, sineSize.height);

    // ─── (2) intrinsic width, floored by the port count ───────────────────
    // `~dac` says less than `~sine 440`, so its box is narrower...
    expect(dacSize.width, lessThan(sineSize.width));
    // ...but never narrower than the two inlets it has to seat (issue #377).
    expect(
      dacSize.width,
      greaterThanOrEqualTo(PatchCanvasConstants.minWidthForPorts(2)),
    );

    // ─── (3) an argument edit re-measures the box ─────────────────────────
    // Double-click the box itself: there is no header to aim at any more.
    // Detected from raw pointer timing, so two quick taps suffice.
    final at = tester.getCenter(boxFor('sine 440'));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(at);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(PatchParamsDialog.fieldKey('frequency')),
      '1234.5678',
    );
    await tester.tap(find.byKey(PatchParamsDialog.doneKey));
    await tester.pumpAndSettle();

    final sine = engine.patcher.graph.nodes.firstWhere(
      (n) => n.type == Obj.dSine,
    );
    expect(engine.patcher.argsOf(sine.id), '1234.5678');
    expect(boxFor('sine 1234.5678'), findsOneWidget);
    expect(boxFor('sine 440'), findsNothing);
    // A longer line needs a longer box — and it got one, without a reload.
    final grown = tester.getSize(boxFor('sine 1234.5678'));
    expect(grown.width, greaterThan(sineSize.width));
    expect(grown.height, sineSize.height);

    // ─── (4) …and the box round-trips with the edit under Ctrl+Z / Ctrl+Y ──
    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(boxFor('sine 440'), findsOneWidget);
    expect(tester.getSize(boxFor('sine 440')), sineSize);

    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(boxFor('sine 1234.5678'), findsOneWidget);

    session.dispose();
    await engine.dispose();
  });
}
