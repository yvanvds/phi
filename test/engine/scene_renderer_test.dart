import 'package:flutter_test/flutter_test.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:vector_math/vector_math_64.dart';

import 'test_doubles/fake_scene_renderer.dart';

void main() {
  test('lifecycle: init flips initialised, dispose flips it back', () {
    final r = FakeSceneRenderer();
    expect(r.initialised, isFalse);
    r.init();
    expect(r.initialised, isTrue);
    r.dispose();
    expect(r.initialised, isFalse);
    expect(r.calls, ['init', 'dispose']);
  });

  test('setCamera records the most recent value', () {
    final r = FakeSceneRenderer();
    final cam = Camera(
      position: Vector3(0, 0, 5),
      target: Vector3.zero(),
    );
    r.setCamera(cam);
    expect(r.lastCamera, same(cam));
    expect(r.calls, ['setCamera']);
  });

  test('setAgents records list with length tag', () {
    final r = FakeSceneRenderer();
    r.setAgents([
      SceneAgent(position: Vector3.zero(), voiceIndex: 0),
      SceneAgent(position: Vector3(1, 0, 0), voiceIndex: 1),
    ]);
    expect(r.lastAgents.length, 2);
    expect(r.lastAgents[1].voiceIndex, 1);
    expect(r.calls, ['setAgents:2']);
  });
}
