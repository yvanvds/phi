import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/patcher/patcher_node_view.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the per-entity patcher gateway (issue #219) drives
/// the Patcher surface through the real [PhiApp] — real rail navigation,
/// layout, and fonts — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched (the real gateway can't run headless).
///
/// `PhiApp` starts the engine on mount, so a wired patcher gateway means the
/// engine builds its `PatcherController` (one gateway instance). Summoning the
/// surface then leaves the new project's empty patch exactly as it was: no
/// demo graph laid into it and nothing mounted on master, because a project
/// always opens with every patch stopped (issue #523).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: summon leaves the empty patch empty and unmounted', (
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

    // Engine started on mount → exactly one gateway instance was created for
    // the open patcher (the multi-instance lifecycle), and nothing is mounted.
    expect(patcherGateway.instances, hasLength(1));
    expect(patcherGateway.mounted, isFalse);

    // Summon the Patcher surface via the left rail.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // The canvas shows the empty patch: no nodes, no cables, and still nothing
    // mounted — the performer hears nothing until they build and press START.
    expect(find.byType(PatcherNodeView), findsNothing);
    expect(engine.patcher.graph.nodes, isEmpty);
    expect(engine.patcher.graph.cables, isEmpty);
    expect(patcherGateway.cables, isEmpty);
    expect(patcherGateway.mounted, isFalse);
    expect(
      patcherGateway.calls.where((c) => c.startsWith('mountAsSource')),
      isEmpty,
    );
    expect(patcherGateway.instances, hasLength(1));

    session.dispose();
    await engine.dispose();
  });
}
