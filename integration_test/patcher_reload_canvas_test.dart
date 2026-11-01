import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/library/patch_entity_strip.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';
import '../test/surfaces/patcher/test_support/lay_demo_chain.dart';

/// End-to-end proof that the Patcher canvas is **rebuilt from a reloaded patch
/// dump** (issue #308) through the real [PhiApp] — real rail navigation, layout
/// and fonts — backed by a [FakePatcherGateway] so no native `libyse.dll` is
/// touched.
///
/// The test lays a slider → sine → dac chain into the open patch and
/// duplicates it. The copy's native instance already holds
/// the graph (the reconciler parsed the duplicated dump) but whose editor mirror
/// starts empty — exactly the reload / rename case. Before the fix that copy
/// showed a blank canvas; now the editor rebuilds from the live instance, so the
/// copy renders the same three nodes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('duplicating a patch opens the copy with its graph rebuilt', (
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

    // Summon the Patcher surface — the engine seeded + opened a default patch —
    // and lay a slider → sine → dac chain into it.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();
    layDemoChain(engine.patcher);
    await tester.pumpAndSettle();

    final library = engine.patchLibrary;
    final first = library.openAddress!;
    expect(find.byType(PatcherNodeView), findsNWidgets(3));

    // Expand the strip and duplicate the open patch through its row context menu.
    await tester.tap(find.byKey(PatchEntityStrip.expandToggleKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PatchEntityStrip.menuKey(first)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('duplicate'));
    await tester.pumpAndSettle();

    // The copy is now the open patch — a different address — and its canvas
    // shows the reconstructed three-node graph.
    final copy = library.openAddress!;
    expect(copy, isNot(first));
    expect(copy.name, endsWith('_copy'));
    expect(find.byType(PatcherNodeView), findsNWidgets(3));
    // The rebuilt editor mirror carries the graph, not just the visuals.
    expect(library.openEditor!.graph.nodes, hasLength(3));
    expect(library.openEditor!.graph.cables, hasLength(2));

    session.dispose();
    await engine.dispose();
  });
}
