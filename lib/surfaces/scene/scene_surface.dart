import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/scene/scene_agent.dart';
import '../../engine/bridge/camera.dart';
import '../../engine/engine.dart';
import '../surface.dart';

/// Phase 1 Scene surface — hosts the macbear-backed 3D viewport.
///
/// Seeds the renderer with one placeholder agent at the origin and an
/// initial orbit camera. macbear's `M3CameraOrbitController` handles
/// orbit / pan / zoom directly; this widget is intentionally minimal.
class SceneSurface extends Surface {
  const SceneSurface({required this.engine, super.key});

  final PhiEngine engine;

  @override
  Widget build(BuildContext context) {
    final renderer = engine.sceneRenderer;
    if (renderer == null) {
      return Container(
        color: PhiColors.bg0,
        alignment: Alignment.center,
        child: const Text(
          'Scene renderer not wired',
          style: TextStyle(color: PhiColors.fg2),
        ),
      );
    }
    return _SceneViewport(engine: engine);
  }
}

/// Inner widget that owns the one-shot seeding of camera + agents.
///
/// Kept separate so the seed runs once on first mount, not on every
/// Flutter rebuild of the surrounding chrome.
class _SceneViewport extends StatefulWidget {
  const _SceneViewport({required this.engine});

  final PhiEngine engine;

  @override
  State<_SceneViewport> createState() => _SceneViewportState();
}

class _SceneViewportState extends State<_SceneViewport> {
  @override
  void initState() {
    super.initState();
    final renderer = widget.engine.sceneRenderer!;
    renderer.setCamera(
      Camera(position: Vector3(6, 6, 4), target: Vector3.zero()),
    );
    renderer.setAgents([
      SceneAgent(position: Vector3.zero(), voiceIndex: 0),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final renderer = widget.engine.sceneRenderer!;
    return Container(color: PhiColors.voidField, child: renderer.buildView());
  }
}
