import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/design/widgets/toggle/phi_toggle.dart';
import 'package:phi/domain/scene/pick_ray.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';
import 'package:vector_math/vector_math_64.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_scene_renderer.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end pick-friendly Scene demo (issue #90) through the real
/// workstation.
///
/// The playback demo clip's notes are too short (agents despawn before a click)
/// and too clustered to exercise the Scene surface's pointer picking by hand.
/// The Scene surface's dev toggle sidesteps that: flipping it on seeds a
/// spread of long-lived, well-separated agents into the shared field — the full
/// path shell → SceneSurface → EngineMidiController → SceneField → renderer —
/// each of which the installed pick handler resolves to a unique agent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('scene: the dev toggle seeds pickable, well-separated agents', (
    tester,
  ) async {
    final renderer = FakeSceneRenderer();
    final engine = PhiEngine(
      FakeYseGateway(),
      sceneRenderer: renderer,
      midiGateway: FakeMidiGateway(),
      telemetryInterval: const Duration(milliseconds: 20),
    );
    final session = SessionState();

    await tester.pumpWidget(PhiApp(engine: engine, session: session));
    await tester.pumpAndSettle();

    // Visit the Scene surface: it seeds a single placeholder agent (voice 0).
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    expect(renderer.lastAgents, hasLength(1));

    // Flip the dev toggle on. The real surface → player path loads the
    // pick-friendly demo set into the shared field and pushes it at the
    // renderer.
    final toggle = find.descendant(
      of: find.byKey(const Key('scene-pick-demo-toggle')),
      matching: find.byType(PhiToggle),
    );
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final agents = renderer.lastAgents;
    expect(agents.length, greaterThan(1));
    // Every agent carries its own voice colour (they are visually distinct).
    expect(agents.map((a) => a.voiceIndex).toSet().length, agents.length);

    // Each agent resolves to a unique key under a ray aimed at it — proof they
    // sit far enough apart to isolate one by hand. Picks go through the real
    // installed handler, which forwards to the engine's shared field.
    final handler = renderer.installedHandler!;
    final keys = <int?>{};
    for (final agent in agents) {
      final p = agent.position;
      final key = handler.pick(
        PickRay(origin: p + Vector3(0, 0, -10), direction: Vector3(0, 0, 1)),
      );
      expect(key, isNotNull, reason: 'each demo agent is pickable');
      keys.add(key);
    }
    expect(keys.length, agents.length, reason: 'no two agents share a key');

    // Flipping it off clears the scene back to empty.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(renderer.lastAgents, isEmpty);

    session.dispose();
    await engine.dispose();
  });
}
