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

  /// How many times the widget returned by [buildView] has mounted / unmounted.
  /// Shell tests use these to assert the Scene view is attached only while Scene
  /// is the selected surface and detaches when it leaves (issue #19), without
  /// pulling in a real GL context. Kept off [calls] so exact call-sequence
  /// assertions elsewhere are unaffected.
  int viewMounts = 0;
  int viewDisposes = 0;
  bool get viewMounted => viewMounts > viewDisposes;

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
  Widget buildView() => _FakeSceneView(
    onMount: () => viewMounts++,
    onDispose: () => viewDisposes++,
  );
}

/// Stand-in for macbear's `M3View` in tests: renders nothing but reports its
/// mount / unmount so a test can observe the Scene view's widget lifecycle.
class _FakeSceneView extends StatefulWidget {
  const _FakeSceneView({required this.onMount, required this.onDispose});

  final VoidCallback onMount;
  final VoidCallback onDispose;

  @override
  State<_FakeSceneView> createState() => _FakeSceneViewState();
}

class _FakeSceneViewState extends State<_FakeSceneView> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
