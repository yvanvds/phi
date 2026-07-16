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

/// End-to-end proof that a grab pulls a live agent while the transport is
/// **stopped** (issue #103), through the real workstation.
///
/// Re-anchoring the playhead and spawns to the engine clock also collapsed the
/// old play/stopped split: `SceneField.step` is now driven off the player's one
/// frame ticker in all cases, and a grab starts that ticker even with nothing
/// playing (the surface no longer owns a separate `stepFromSurface`). This
/// drives the full path shell → SceneSurface → EngineMidiController →
/// SceneField, seeding pickable agents with the dev demo (no playback), then
/// grabbing one and dragging it — the agent must follow with the transport
/// stopped.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('scene: a grab drags an agent while the transport is stopped', (
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

    // Open the Scene and seed the pick-friendly demo set — the transport is
    // never started, so everything here happens on a stopped Scene.
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    final toggle = find.descendant(
      of: find.byKey(const Key('scene-pick-demo-toggle')),
      matching: find.byType(PhiToggle),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(session.isPlaying, isFalse);
    expect(renderer.lastAgents.length, greaterThan(1));

    // Pick one agent through the real installed handler and grab it.
    final handler = renderer.installedHandler!;
    final target = renderer.lastAgents.first.position.clone();
    final key = handler.pick(
      PickRay(origin: target + Vector3(0, 0, -10), direction: Vector3(0, 0, 1)),
    );
    expect(key, isNotNull, reason: 'the demo agent is pickable');
    handler.grab(key!);

    final before = handler.agentPosition(key)!.clone();
    // Drag the held target well away on +Y and let a few frames pull the agent.
    handler.moveGrabTo(before + Vector3(0, 6, 0));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }

    final after = handler.agentPosition(key)!;
    expect(
      after.y,
      greaterThan(before.y),
      reason: 'the grab pulled the agent on a stopped transport',
    );
    expect(after.y, lessThanOrEqualTo(before.y + 6 + 1e-6));

    handler.releaseGrab();
    session.dispose();
    await engine.dispose();
  });
}
