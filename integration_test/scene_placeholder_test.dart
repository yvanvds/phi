import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/bridge/placeholder_scene_renderer.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:phi/surfaces/scene/scene_surface.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end: with the 3D renderer removed (issue #456), the real app opens
/// the Scene surface on the production placeholder renderer — it shows the
/// notice, and the surface's own wiring (camera seed, pick demo pushing agents
/// at the renderer) still runs against it without errors.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('scene: opens on the placeholder renderer and shows its notice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final renderer = PlaceholderSceneRenderer();
    final engine = PhiEngine(
      FakeYseGateway(),
      sceneRenderer: renderer,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );

    await tester.pumpWidget(PhiApp(engine: engine, session: SessionState()));
    await tester.pumpAndSettle();
    expect(find.text(PlaceholderSceneRenderer.notice), findsNothing);

    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();

    expect(find.byType(SceneSurface), findsOneWidget);
    expect(find.text(PlaceholderSceneRenderer.notice), findsOneWidget);
    expect(renderer.camera, isNotNull, reason: 'the surface seeds a camera');
    expect(renderer.agents, hasLength(1), reason: 'and one seed agent');

    // The dev pick demo still loads agents through the real surface → player
    // path into the placeholder.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('scene-pick-demo-toggle')),
        matching: find.byType(PhiToggle),
      ),
    );
    await tester.pumpAndSettle();
    expect(renderer.agents.length, greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
