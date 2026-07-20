import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/patcher/patch_node_frame.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_patcher_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end proof that the per-entity patcher gateway (issue #219) drives
/// the Patcher surface through the real [PhiApp] — real rail navigation,
/// layout, and fonts — backed by a [FakePatcherGateway] so no native
/// `libyse.dll` is touched (the real gateway can't run headless).
///
/// `PhiApp` starts the engine on mount, so a wired patcher gateway means the
/// engine builds its `PatcherController` (one gateway instance); summoning
/// the surface seeds the demo graph and, once a `~dac` exists, mounts the
/// patcher as a source. This is the one cross-layer path the multi-instance
/// generalisation touches — surface → controller → gateway.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('patcher: summon seeds the demo graph and mounts as a source', (
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
    // the open patcher (the multi-instance lifecycle), and nothing is mounted
    // yet (mounting an empty patcher crashes the audio thread).
    expect(patcherGateway.instances, hasLength(1));
    expect(patcherGateway.mounted, isFalse);

    // Summon the Patcher surface via the left rail.
    await tester.tap(railFor(SurfaceId.patcher));
    await tester.pumpAndSettle();

    // The surface seeds slider → sine → dac (3 nodes, 2 cables) and, now that
    // a `~dac` exists, mounts the patcher as a source. All three ops routed
    // through the single instance the controller owns.
    expect(find.byType(PatchNodeFrame), findsNWidgets(3));
    expect(engine.patcher.graph.cables, hasLength(2));
    expect(patcherGateway.cables, hasLength(2));
    expect(patcherGateway.mounted, isTrue);
    expect(patcherGateway.instances, hasLength(1));

    session.dispose();
    await engine.dispose();
  });
}
