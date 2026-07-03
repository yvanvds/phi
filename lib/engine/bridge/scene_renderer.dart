import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../domain/scene/scene_agent.dart';
import 'camera.dart';
import 'scene_agent_sink.dart';
import 'scene_pick_handler.dart';

/// Abstract renderer for the 3D Scene surface.
///
/// `SceneSurface` depends on this interface, not on any concrete 3D engine,
/// so tests can swap in a fake and the production code is the only place a
/// real renderer's API is touched. The current production implementation
/// uses `package:macbear_3d`; see `macbear_scene_renderer.dart`.
///
/// Extends [SceneAgentSink] so the MIDI player can push live spawns straight
/// at a renderer without knowing about cameras or lifecycle.
abstract interface class SceneRenderer implements SceneAgentSink {
  /// Allocate internal state. Called from `PhiEngine.start()`.
  void init();

  /// Release internal state. Called from `PhiEngine.stop()`.
  void dispose();

  /// Set the current camera. Applied on the next frame.
  void setCamera(Camera camera);

  /// Highlight the agent at [worldPosition] as the current selection, or clear
  /// the highlight with `null`. Reflected on the next frame. The Scene surface
  /// pushes the selected agent's *live* position here each frame so the
  /// highlight tracks the moving agent.
  void setSelection(Vector3? worldPosition);

  /// Wire the pointer-picking / grab input path, routing picks and grabs
  /// through [handler]. Replaces the renderer's default camera-only input
  /// controller; the built-in orbit / pan / zoom behaviour still runs for
  /// misses and non-left-button gestures.
  void installPicking(ScenePickHandler handler);

  /// Set the current agents. Reflected on the next frame.
  @override
  void setAgents(List<SceneAgent> agents);

  /// Mark the surface on- or off-stage. When the Scene surface is offstage
  /// the renderer may stop its render loop to save GPU/power; it must resume
  /// and reflect any agent updates that arrived while offstage when called
  /// with `true` again. Safe to call before [init] — the request is honoured
  /// once the renderer's context comes up.
  void setVisible(bool visible);

  /// Widget that mounts the renderer into the Flutter tree. `SceneSurface`
  /// calls this from its `build` and inserts the result into its subtree.
  Widget buildView();
}
