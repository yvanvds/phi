import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/placeholder_scene_renderer.dart';
import 'package:vector_math/vector_math_64.dart';

/// The renderer production wires while Phi has no 3D renderer (issue #456).
void main() {
  test('accepts every renderer call and keeps camera + agents', () {
    final renderer = PlaceholderSceneRenderer()..init();
    final camera = Camera(position: Vector3(1, 2, 3), target: Vector3.zero());
    final agents = [SceneAgent(position: Vector3.zero(), voiceIndex: 0)];

    renderer
      ..setVisible(false)
      ..setVisible(true)
      ..setCamera(camera)
      ..setAgents(agents)
      ..setSelection(Vector3(1, 0, 0))
      ..setSelection(null);

    expect(renderer.camera, same(camera));
    expect(renderer.agents, same(agents));

    renderer.dispose();
    expect(renderer.agents, isEmpty);
  });

  testWidgets('its view shows the "3D view unavailable" notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PlaceholderSceneRenderer().buildView(),
      ),
    );
    expect(find.text(PlaceholderSceneRenderer.notice), findsOneWidget);
  });
}
