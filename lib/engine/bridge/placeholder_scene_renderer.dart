import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/scene/scene_agent.dart';
import 'camera.dart';
import 'scene_pick_handler.dart';
import 'scene_renderer.dart';

/// Production [SceneRenderer] while Phi has no 3D renderer (issue #456).
///
/// The `macbear_3d` viewport was a proof of concept, and its `flutter_angle`
/// dependency blocked the Linux build, so it was removed on every platform.
/// Bringing a 3D renderer back is tracked in issue #455. Until then this
/// renderer keeps the [SceneRenderer] seam whole: it accepts every call (the
/// MIDI player still pushes live agents, the Scene surface still seeds its
/// camera and installs picking) and draws a static notice instead of a
/// viewport.
class PlaceholderSceneRenderer implements SceneRenderer {
  /// The notice the [buildView] widget shows.
  static const String notice = '3D view unavailable';

  Camera? _camera;
  List<SceneAgent> _agents = const [];

  /// The last camera the surface set, or `null` before the first.
  Camera? get camera => _camera;

  /// The agents most recently pushed by the surface or the MIDI player.
  List<SceneAgent> get agents => _agents;

  @override
  void init() {}

  @override
  void dispose() {
    _agents = const [];
  }

  @override
  void setCamera(Camera camera) => _camera = camera;

  @override
  void setSelection(Vector3? worldPosition) {}

  @override
  void installPicking(ScenePickHandler handler) {}

  @override
  void setAgents(List<SceneAgent> agents) => _agents = agents;

  @override
  void setVisible(bool visible) {}

  @override
  Widget buildView() => const ColoredBox(
    color: PhiColors.bg0,
    child: Center(
      child: Text(
        notice,
        key: Key('scene-placeholder-notice'),
        style: TextStyle(color: PhiColors.fg2),
      ),
    ),
  );
}
