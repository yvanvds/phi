import 'package:flutter/widgets.dart';

import '../../domain/scene/scene_agent.dart';
import 'camera.dart';

/// Abstract renderer for the 3D Scene surface.
///
/// `SceneSurface` depends on this interface, not on any concrete 3D engine,
/// so tests can swap in a fake and the production code is the only place a
/// real renderer's API is touched. The current production implementation
/// uses `package:macbear_3d`; see `macbear_scene_renderer.dart`.
abstract interface class SceneRenderer {
  /// Allocate internal state. Called from `PhiEngine.start()`.
  void init();

  /// Release internal state. Called from `PhiEngine.stop()`.
  void dispose();

  /// Set the current camera. Applied on the next frame.
  void setCamera(Camera camera);

  /// Set the current agents. Reflected on the next frame.
  void setAgents(List<SceneAgent> agents);

  /// Widget that mounts the renderer into the Flutter tree. `SceneSurface`
  /// calls this from its `build` and inserts the result into its subtree.
  Widget buildView();
}
