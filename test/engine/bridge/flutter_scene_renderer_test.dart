import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/flutter_scene_renderer.dart';
import 'package:phi/engine/bridge/flutter_scene_view.dart';
import 'package:phi/engine/bridge/scene_view_status.dart';
import 'package:vector_math/vector_math_64.dart';

/// The production renderer under `flutter test`, which has no Impeller and so
/// no Flutter GPU: the seam keeps working and the view shows its notice. The
/// drawing itself is covered by `integration_test/scene_3d_view_test.dart`,
/// which runs the real runner with Flutter GPU on.
void main() {
  test('accepts every call before the engine is up and keeps its state', () {
    final renderer = FlutterSceneRenderer();
    final agents = [SceneAgent(position: Vector3(1, 2, 3), voiceIndex: 2)];
    renderer
      ..setCamera(Camera(position: Vector3(0, -10, 0), target: Vector3.zero()))
      ..setAgents(agents)
      ..setSelection(Vector3(1, 2, 3));
    expect(renderer.status, SceneViewStatus.idle);
    expect(renderer.agents.single.position, agents.single.position);
    expect(renderer.selection, Vector3(1, 2, 3));
    expect(renderer.orbit.position.y, closeTo(-10, 1e-9));
    renderer.dispose();
    expect(renderer.agents, isEmpty);
    expect(renderer.selection, isNull);
  });

  test('changes tick for each update, and hold while offstage', () {
    final renderer = FlutterSceneRenderer();
    var ticks = 0;
    renderer.changes.addListener(() => ticks++);
    renderer.setAgents(const []);
    expect(ticks, 1);
    // An unchanged selection does not redraw.
    renderer
      ..setSelection(null)
      ..setSelection(Vector3(1, 0, 0))
      ..setSelection(Vector3(1, 0, 0));
    expect(ticks, 2);

    renderer.setVisible(false);
    renderer
      ..setAgents(const [])
      ..setSelection(null)
      ..markCameraMoved();
    expect(ticks, 2, reason: 'nothing redraws offstage');
    renderer.setVisible(true);
    expect(ticks, 3, reason: 'coming back flushes what was missed, once');
    renderer
      ..setVisible(false)
      ..setVisible(true);
    expect(ticks, 3, reason: 'nothing was missed this time');
  });

  testWidgets('without Flutter GPU the view shows the unavailable notice', (
    tester,
  ) async {
    final renderer = FlutterSceneRenderer()..init();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: renderer.buildView(),
      ),
    );
    await tester.runAsync(renderer.start);
    await tester.pump();

    expect(renderer.status, SceneViewStatus.unavailable);
    expect(renderer.failure, isNotNull);
    expect(renderer.graph, isNull);
    expect(find.byKey(FlutterSceneView.unavailableKey), findsOneWidget);
    expect(find.text(FlutterSceneRenderer.unavailableNotice), findsOneWidget);
    expect(find.byKey(FlutterSceneView.viewportKey), findsNothing);

    // The seam still takes every call.
    renderer
      ..setAgents([SceneAgent(position: Vector3.zero())])
      ..setSelection(Vector3.zero())
      ..setVisible(false)
      ..setVisible(true);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Dispose resets it; a later start tries again.
    renderer.dispose();
    expect(renderer.status, SceneViewStatus.idle);
  });
}
