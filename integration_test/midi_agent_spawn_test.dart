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

/// End-to-end spatial agent spawn through the real workstation (issue #37).
///
/// The `spawn · agent @ p,v` chip in the default chain is a real
/// [AgentSpawnTransform] now. Driving the real transport must turn the
/// clip's note-ons into live `SceneAgent`s pushed at the wired renderer — the
/// full path: session transport → shell listener → EngineMidiController →
/// AgentSpawnTransform → SceneAgentSink. A [FakeSceneRenderer] stands in for
/// macbear and records every `setAgents` call.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder railFor(SurfaceId id) =>
      find.byWidgetPredicate((w) => w is RailButton && w.label == id.label);

  testWidgets('midi: playing the demo clip spawns scene agents', (
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
    // spawned agent carries voice index 1 and a finite in-range position.
    expect(renderer.lastAgents, isNotEmpty);
    for (final agent in renderer.lastAgents) {
      expect(agent.voiceIndex, 1);
      expect(agent.position.x, inInclusiveRange(-1, 1));
      expect(agent.position.y, inInclusiveRange(-1, 1));
      expect(agent.position.z, inInclusiveRange(-1, 1));
    }
    // The player drove the sink: at least one note-on-triggered setAgents fired.
    expect(
      renderer.calls.where((c) => c.startsWith('setAgents')).length,
      greaterThan(1),
    );

    // Stopping the transport clears the scene back to empty.
    session.stop();
    await tester.pump(const Duration(milliseconds: 20));
    expect(renderer.lastAgents, isEmpty);

    session.dispose();
    await engine.dispose();
  });
}
