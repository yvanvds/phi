import 'package:flutter/widgets.dart';
import 'package:phi/domain/scene/scene_agent.dart';
import 'package:phi/engine/bridge/camera.dart';
import 'package:phi/engine/bridge/scene_pick_handler.dart';
import 'package:phi/engine/bridge/scene_renderer.dart';
import 'package:vector_math/vector_math_64.dart';

/// In-memory [SceneRenderer] used in unit and widget tests.
///
/// Records every call so tests can assert call sequence without depending
/// on a real 3D engine.
class FakeSceneRenderer implements SceneRenderer {
  final List<String> calls = [];
  bool initialised = false;
  Camera? lastCamera;
  List<SceneAgent> lastAgents = const [];
  bool? lastVisible;
  Vector3? lastSelection;
  ScenePickHandler? installedHandler;

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
  void setVisible(bool visible) {
    calls.add('setVisible:$visible');
    lastVisible = visible;
  }

  @override
  void setSelection(Vector3? worldPosition) {
    calls.add('setSelection:${worldPosition == null ? 'null' : 'pos'}');
    lastSelection = worldPosition;
  }

  @override
  void installPicking(ScenePickHandler handler) {
    calls.add('installPicking');
    installedHandler = handler;
  }

  @override
  Widget buildView() => const SizedBox.shrink();
}
