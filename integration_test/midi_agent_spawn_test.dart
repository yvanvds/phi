import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:phi/app.dart';
import 'package:phi/domain/session/session_state.dart';
import 'package:phi/engine/engine.dart';
import 'package:phi/shell/left_rail/rail_button.dart';
import 'package:phi/shell/left_rail/surface_id.dart';

import '../test/engine/test_doubles/fake_midi_gateway.dart';
import '../test/engine/test_doubles/fake_scene_renderer.dart';
import '../test/engine/test_doubles/fake_yse_gateway.dart';

/// End-to-end spatial agent spawn — and now live motion — through the real
/// workstation (issues #37, #79).
///
/// The `spawn · agent @ p,v` chip in the default chain is a real
/// [AgentSpawnTransform] with a gentle +Z drift (the scene camera's up axis is
/// +Z, so agents rise on screen — issue #89). Driving the real transport
/// must turn the clip's note-ons into live `SceneAgent`s that the scene field
/// advances each tick and pushes at the wired renderer — the full path:
/// session transport → shell listener → EngineMidiController → SceneField.step
/// → SceneAgentSink. A [FakeSceneRenderer] stands in for macbear and records
/// every `setAgents` call.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: playing the demo clip spawns agents that move', (
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

    // Visit the Scene surface: it seeds a single placeholder agent at the
    // origin (voice 0). This is the baseline the player will overwrite.
    await tester.tap(railFor(SurfaceId.scene));
    await tester.pumpAndSettle();
    expect(renderer.lastAgents, hasLength(1));
    expect(renderer.lastAgents.single.voiceIndex, 0);

    // Start the transport through the real session → shell → player path.
    session.play();
    // A short real-time pump crosses the first note-on (beat 0). Use pump, not
    // pumpAndSettle — the looping playhead timer never settles.
    await tester.pump(const Duration(milliseconds: 40));

    // The scene now holds player-spawned agents, not the placeholder. Every
    // demo note is routed to channel 1 by the `route · osc.saw` chip, so each
    // spawned agent carries voice index 1 and a finite position.
    expect(renderer.lastAgents, isNotEmpty);
    for (final agent in renderer.lastAgents) {
      expect(agent.voiceIndex, 1);
      expect(agent.position.x.isFinite, isTrue);
      expect(agent.position.y.isFinite, isTrue);
      expect(agent.position.z.isFinite, isTrue);
    }
    // The player drove the sink: at least one note-on-triggered setAgents fired.
    expect(
      renderer.calls.where((c) => c.startsWith('setAgents')).length,
      greaterThan(1),
    );

    // Prove the field actually steps *and* that the drift now rides the +Z
    // (up) axis (issue #89). Sweep across a couple of full loops, tracking the
    // highest Z and highest Y any agent reaches.
    //
    // Spawn Z is the time axis: a note's start beat (max 3.5 in `phraseA`)
    // remapped from [0, 16] beats onto [-1, 1], so no fresh agent can spawn
    // above resolve(3.5) = -0.5625 (upstream tempo-locking only lowers starts,
    // pushing fresh spawns further below the cap). The only way to observe a Z
    // above that cap is the +Z drift carrying a live agent past its spawn
    // point — so `maxZ > -0.5625` is a clean signature of upward live motion.
    //
    // Spawn Y is the velocity axis, capped at 0.8 (velocity 0.9 -> +0.8). With
    // the drift moved off Y, no agent's Y ever exceeds its spawn Y, so
    // `maxY <= 0.8` guards against the old +Y drift regressing.
    const spawnZCap = -0.5625; // resolve(start 3.5) on the time axis
    const spawnYCap = 0.8; // resolve(velocity 0.9) on the velocity axis
    var maxZ = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (var i = 0; i < 140; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      for (final agent in renderer.lastAgents) {
        if (agent.position.z > maxZ) maxZ = agent.position.z;
        if (agent.position.y > maxY) maxY = agent.position.y;
      }
    }
    expect(
      maxZ,
      greaterThan(spawnZCap),
      reason: 'a live agent should have drifted above the -0.5625 spawn-Z cap',
    );
    expect(
      maxY,
      lessThanOrEqualTo(spawnYCap + 1e-9),
      reason: 'the drift left the Y axis, so no agent should exceed spawn Y',
    );

    // Stopping the transport clears the scene back to empty.
    session.stop();
    await tester.pump(const Duration(milliseconds: 20));
    expect(renderer.lastAgents, isEmpty);

    session.dispose();
    await engine.dispose();
  });
}
