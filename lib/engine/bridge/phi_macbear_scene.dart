import 'package:flutter/material.dart' hide Colors, Matrix4;
import 'package:macbear_3d/macbear_3d.dart' as m3;
import 'package:vector_math/vector_math.dart' as vm32;
import 'package:vector_math/vector_math_64.dart' as vm64;

import '../../design/tokens/phi_colors.dart';
import '../../domain/scene/scene_agent.dart';
import 'camera.dart';
import 'phi_scene_pick_controller.dart';
import 'scene_pick_handler.dart';

/// Concrete `M3Scene` that draws one Phi-styled glowing dot per agent.
///
/// Each agent renders as two concentric spheres:
///   - an opaque inner *core* in the voice's full saturated colour, and
///   - a translucent outer *halo* in the corresponding `voiceSoft` token.
///
/// Against the dark substrate (`PhiColors.voidField`) the pair reads as a
/// glowing dot per the design system. macbear's own
/// `M3CameraOrbitController` handles orbit / pan / zoom; we only seed the
/// initial pose.
class PhiMacbearScene extends m3.M3Scene {
  static const double _coreRadius = 0.18;
  static const double _haloRadius = 0.55;

  /// The selection halo sits just outside an agent's own halo, so the picked
  /// agent reads as ringed by a brighter shell.
  static const double _selectionRadius = 0.74;

  List<SceneAgent> _pending = const [];
  Camera? _pendingCamera;
  vm64.Vector3? _selection;
  bool _dirty = false;

  /// Replace the agents that will render on the next frame.
  void setAgents(List<SceneAgent> agents) {
    _pending = List<SceneAgent>.unmodifiable(agents);
    _dirty = true;
  }

  /// Replace the camera state applied on the next frame.
  void setCamera(Camera camera) {
    _pendingCamera = camera;
    _dirty = true;
  }

  /// Highlight the agent at [worldPosition], or clear the highlight with
  /// `null`. Only marks the frame dirty when the selection actually moves, so
  /// the surface can push this every tick cheaply.
  void setSelection(vm64.Vector3? worldPosition) {
    if (_selectionEquals(worldPosition)) return;
    _selection = worldPosition?.clone();
    _dirty = true;
  }

  /// Install the pointer-picking input controller, routing picks and grabs
  /// through [handler] and falling back to a fresh orbit controller for misses
  /// and non-left-button gestures.
  void installPicking(ScenePickHandler handler) {
    inputController = PhiScenePickController(
      camera: camera,
      handler: handler,
      fallback: m3.M3CameraOrbitController(camera),
      // Pointer positions arrive in logical pixels; the app engine tracks the
      // logical viewport size in the same units.
      viewportSize: () {
        final engine = m3.M3AppEngine.instance;
        return (engine.appWidth.toDouble(), engine.appHeight.toDouble());
      },
    );
  }

  bool _selectionEquals(vm64.Vector3? other) {
    final current = _selection;
    if (current == null || other == null) {
      return current == null && other == null;
    }
    return current.x == other.x && current.y == other.y && current.z == other.z;
  }

  @override
  Future<void> load() async {
    if (isLoaded) return;
    await super.load();
    camera.csmCount = 0;
    m3.M3AppEngine.backgroundColor = _vec3From(PhiColors.voidField);
    _applyPendingCamera();
    _rebuildEntities();
  }

  @override
  void update(double delta) {
    if (_dirty) {
      _applyPendingCamera();
      _rebuildEntities();
      _dirty = false;
    }
    super.update(delta);
  }

  void _applyPendingCamera() {
    final pending = _pendingCamera;
    if (pending == null) return;
    camera.setLookat(
      _toVm32(pending.position),
      _toVm32(pending.target),
      vm32.Vector3(0, 0, 1),
    );
    // Apply the pose once. `_dirty` is also raised by every agent push, so
    // re-applying here each frame would snap the camera back to the seed and
    // fight the orbit controller the whole time the transport runs.
    _pendingCamera = null;
  }

  void _rebuildEntities() {
    entities.clear();
    _addSelectionHalo();
    for (final agent in _pending) {
      final position = _toVm32(agent.position);
      final core = _voiceColor(agent.voiceIndex, soft: false);
      final halo = _voiceColor(agent.voiceIndex, soft: true);

      addMesh(m3.M3Mesh(m3.M3SphereGeom(_coreRadius)), position)
        ..color = core
        ..mesh!.subMeshes.first.mtr.setMatte();

      final haloEntity = addMesh(
        m3.M3Mesh(m3.M3SphereGeom(_haloRadius)),
        position,
      )..color = halo;
      final haloMtr = haloEntity.mesh!.subMeshes.first.mtr;
      haloMtr.setMatte();
      haloMtr.alphaMode = m3.M3AlphaMode.blend;
    }
  }

  /// Draw the selection halo, if any — a translucent bright shell just outside
  /// the picked agent's own halo, so the current selection reads as ringed.
  void _addSelectionHalo() {
    final selection = _selection;
    if (selection == null) return;
    final entity = addMesh(
      m3.M3Mesh(m3.M3SphereGeom(_selectionRadius)),
      _toVm32(selection),
    )..color = _selectionColor;
    final mtr = entity.mesh!.subMeshes.first.mtr;
    mtr.setMatte();
    mtr.alphaMode = m3.M3AlphaMode.blend;
  }

  static vm32.Vector3 _toVm32(vm64.Vector3 v) => vm32.Vector3(v.x, v.y, v.z);

  /// Bright, semi-transparent shell colour for the selection halo — pure white
  /// at a high enough alpha to read clearly over the dark void and any voice
  /// colour, while still letting the picked agent show through.
  static final vm32.Vector4 _selectionColor = vm32.Vector4(1, 1, 1, 0.6);

  static vm32.Vector3 _vec3From(Color c) => vm32.Vector3(c.r, c.g, c.b);

  static vm32.Vector4 _voiceColor(int voiceIndex, {required bool soft}) {
    const core = <Color>[
      PhiColors.voice1,
      PhiColors.voice2,
      PhiColors.voice3,
      PhiColors.voice4,
      PhiColors.voice5,
      PhiColors.voice6,
    ];
    const halo = <Color>[
      PhiColors.voice1Soft,
      PhiColors.voice2Soft,
      PhiColors.voice3Soft,
      PhiColors.voice4Soft,
      PhiColors.voice5Soft,
      PhiColors.voice6Soft,
    ];
    final i = voiceIndex.clamp(0, core.length - 1);
    final c = soft ? halo[i] : core[i];
    return vm32.Vector4(c.r, c.g, c.b, c.a);
  }
}
