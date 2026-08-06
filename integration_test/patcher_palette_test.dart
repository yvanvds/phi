import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/patch_object_descriptor.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/palette/patcher_palette.dart';
import 'package:phi/surfaces/patcher/patcher_canvas.dart';
import 'package:phi/surfaces/patcher/reference/patch_reference_panel.dart';
import 'package:yse/yse.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the patcher palette + reference panel (issue #221)
/// drive the real [PhiApp] — real rail navigation, layout, and fonts — off the
/// gateway's metadata descriptors, backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched. Covers the three user-visible legs: the palette's
/// PCategory sections, drag-to-create landing a node on the canvas, and tapping
/// a palette entry documenting it in the reference panel.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: palette sections, drag-create, and reference panel', (
    tester,
  ) async {
    final patcherGateway = FakePatcherGateway();
    final engine = PhiEngine(
      FakeYseGateway(),
      patcherGateway: patcherGateway,
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Summon the Patcher surface via the left rail.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // Palette: category sections fed by the gateway metadata, with the subpatch
    // type filtered out (design §10 decision 2).
    expect(
      find.byKey(PatcherPalette.sectionKey(PatchObjectCategory.oscillator)),
      findsOneWidget,
    );
    expect(find.byKey(PatcherPalette.entryKey(Obj.dSine)), findsOneWidget);
    expect(find.byKey(PatcherPalette.entryKey(Obj.patcher)), findsNothing);

    // Reference panel starts empty; tapping a palette entry renders the engine's
    // own documentation for it.
    expect(find.byKey(PatchReferencePanel.emptyKey), findsOneWidget);
    await tester.tap(find.byKey(PatcherPalette.entryKey(Obj.dSine)));
    await tester.pumpAndSettle();
    expect(find.byKey(PatchReferencePanel.emptyKey), findsNothing);
    expect(find.text('sine oscillator'), findsOneWidget);

    // Drag-to-create: drop a slider onto the canvas → a fourth node lands.
    final canvas = find.byType(PatcherCanvas);
    final before = engine.patcher.graph.nodes.length;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(PatcherPalette.entryKey(Obj.gSlider))),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(canvas));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(engine.patcher.graph.nodes, hasLength(before + 1));
    expect(
      engine.patcher.graph.nodes.any((n) => n.type == Obj.gSlider),
      isTrue,
    );

    // The reference panel followed the drop (issue #437): it now documents the
    // slider that just landed, not the `~sine` the palette tap left it on.
    final panel = find.byType(PatchReferencePanel);
    expect(
      find.descendant(of: panel, matching: find.text('horizontal slider')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('sine oscillator')),
      findsNothing,
    );

    session.dispose();
    await engine.dispose();
  });
}
