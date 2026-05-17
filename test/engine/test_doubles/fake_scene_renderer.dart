import 'package:flutter/widgets.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/scene_renderer.dart';

/// In-memory [SceneRenderer] used in unit and widget tests.
///
/// Records every call so tests can assert call sequence without depending
/// on a real 3D engine.
class FakeSceneRenderer implements SceneRenderer {
  final List<String> calls = [];
  bool initialised = false;
  Camera? lastCamera;
  List<SceneAgent> lastAgents = const [];

  @override
  void init() {
    calls.add('init');
    initialised = true;
  }

  @override
  void dispose() {
    calls.add('dispose');
    initialised = false;
  }

  @override
  void setCamera(Camera camera) {
    calls.add('setCamera');
    lastCamera = camera;
  }

  @override
  void setAgents(List<SceneAgent> agents) {
    calls.add('setAgents:${agents.length}');
    lastAgents = agents;
  }

  @override
  Widget buildView() => const SizedBox.shrink();
}
