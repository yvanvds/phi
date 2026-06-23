import 'package:flutter/widgets.dart';
import 'package:macbear_3d/macbear_3d.dart' as m3;

import '../../domain/scene/scene_agent.dart';
import 'camera.dart';
import 'phi_macbear_scene.dart';
import 'scene_renderer.dart';

/// Production [SceneRenderer] backed by `package:macbear_3d`.
///
/// macbear's `M3AppEngine` is a process-wide singleton. We hand it our
/// [PhiMacbearScene] via `onDidInit` so the scene goes live as soon as the
/// ANGLE context comes up the first time an `M3View` mounts.
class MacbearSceneRenderer implements SceneRenderer {
  final PhiMacbearScene _scene = PhiMacbearScene();
  bool _wired = false;

  /// Desired on-stage state. Defaults to `true` (macbear's own ticker runs
  /// once its context comes up); the shell overrides this via [setVisible].
  bool _visible = true;

  @override
  void init() {
    if (_wired) return;
    _wired = true;
    final engine = m3.M3AppEngine.instance;
    engine.onDidInit = () async {
      await engine.setScene(_scene);
      // `setScene` ends by resuming the ticker. Re-apply the latest
      // visibility request, which may have arrived (as a no-op) before the
      // GL context was live.
      _applyVisibility(engine);
    };
  }

  @override
  void dispose() {
    // macbear's singleton owns the underlying GL context for the process
    // lifetime; we cannot tear it down without breaking later remounts.
    // Clearing the scene's agents is the safe equivalent.
    _scene.setAgents(const []);
  }

  @override
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _applyVisibility(m3.M3AppEngine.instance);
  }

  /// Pause or resume macbear's process-wide render ticker to match [_visible].
  /// Both calls no-op until macbear has initialised, so this is also invoked
  /// from `onDidInit` to apply a request that landed before the context came
  /// up.
  void _applyVisibility(m3.M3AppEngine engine) {
    if (_visible) {
      engine.resume();
    } else {
      engine.pause();
    }
  }

  @override
  void setCamera(Camera camera) => _scene.setCamera(camera);

  @override
  void setAgents(List<SceneAgent> agents) => _scene.setAgents(agents);

  @override
  Widget buildView() => const m3.M3View();
}
