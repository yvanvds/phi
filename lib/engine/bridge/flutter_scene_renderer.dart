import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math_64.dart';

import '../../domain/scene/scene_agent.dart';
import 'camera.dart';
import 'flutter_scene_graph.dart';
import 'flutter_scene_space.dart';
import 'flutter_scene_view.dart';
import 'scene_orbit_camera.dart';
import 'scene_pick_handler.dart';
import 'scene_pointer_controller.dart';
import 'scene_renderer.dart';
import 'scene_view_status.dart';

/// Production [SceneRenderer], drawn by `flutter_scene` on Flutter GPU
/// (issue #455).
///
/// Flutter GPU renders through Impeller, Flutter's own renderer, so the same
/// code draws on Linux and Windows with no native plugin; the runners switch
/// it on (`fl_dart_project_set_enable_flutter_gpu` / `set_enable_flutter_gpu`).
/// Where it is off — the headless `flutter test` runner has no Impeller — the
/// renderer reports [SceneViewStatus.unavailable] and its view shows a notice,
/// while the seam keeps accepting every call.
///
/// The renderer owns the orbit camera and the pointer controller; the engine
/// scene graph ([FlutterSceneGraph]) exists only once the engine's static
/// resources are up. Agent, selection and camera updates mark the view dirty
/// through [changes], and the view redraws on demand — an idle Scene schedules
/// no frames.
class FlutterSceneRenderer implements SceneRenderer {
  FlutterSceneRenderer() {
    pointer = ScenePointerController(
      camera: orbit,
      rayThrough: (position, viewport) =>
          FlutterSceneSpace.rayThrough(orbit.camera, position, viewport),
    );
  }

  /// The notice the view shows when Flutter GPU is not available.
  static const String unavailableNotice = '3D view unavailable';

  /// The line under [unavailableNotice] saying why.
  static const String unavailableDetail =
      'Flutter GPU (Impeller) is not available here.';

  /// The viewport's orbit camera, seeded by [setCamera].
  final SceneOrbitCamera orbit = SceneOrbitCamera(
    Camera(position: Vector3(6, 6, 4), target: Vector3.zero()),
  );

  /// Routes the viewport's pointer into picks, grabs and camera moves.
  late final ScenePointerController pointer;

  /// Bumped on every change the view must reflect.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);
  SceneViewStatus _status = SceneViewStatus.idle;
  Object? _failure;
  FlutterSceneGraph? _graph;
  List<SceneAgent> _agents = const [];
  Vector3? _selection;
  bool _visible = true;
  bool _dirtyWhileHidden = false;

  /// Fires when the view should redraw (or rebuild for a status change).
  /// Quiet while the Scene is offstage; [setVisible] flushes what was missed.
  ValueListenable<int> get changes => _revision;

  /// Where bringing the 3D view up stands.
  SceneViewStatus get status => _status;

  /// Why the view is [SceneViewStatus.unavailable], or `null`.
  Object? get failure => _failure;

  /// The engine scene graph, once [status] is [SceneViewStatus.ready].
  FlutterSceneGraph? get graph => _graph;

  /// The agents most recently pushed by the surface or the MIDI player.
  List<SceneAgent> get agents => _agents;

  /// The world position of the selection highlight, or `null` for none.
  Vector3? get selection => _selection?.clone();

  /// Whether the Scene is on stage.
  bool get visible => _visible;

  /// The engine camera for the current orbit pose.
  fs.Camera get engineCamera => FlutterSceneSpace.engineCamera(orbit.camera);

  /// Where the scene-space [point] lands in a [viewport] (logical pixels), or
  /// `null` when it sits behind the camera. The inverse of the pointer's pick
  /// ray, so tests and overlays can find an agent on screen.
  Offset? project(Vector3 point, Size viewport) =>
      FlutterSceneSpace.project(orbit.camera, point, viewport);

  /// Start loading the engine's static resources, once. Completes when the
  /// view is ready or known unavailable; never throws.
  Future<void> start() {
    if (_status != SceneViewStatus.idle) return _started ?? Future.value();
    _status = SceneViewStatus.starting;
    return _started = _bringUp(++_generation);
  }

  Future<void>? _started;

  /// Bumped by every [start] and [dispose], so a bring-up that a [dispose]
  /// overtook while it awaited the engine drops its result.
  int _generation = 0;

  Future<void> _bringUp(int generation) async {
    try {
      await fs.Scene.initializeStaticResources();
      if (generation != _generation) return;
      final graph = FlutterSceneGraph()
        ..setAgents(_agents)
        ..setSelection(_selection);
      _graph = graph;
      _status = SceneViewStatus.ready;
    } catch (error) {
      if (generation != _generation) return;
      _failure = error;
      _status = SceneViewStatus.unavailable;
      debugPrint('Scene: 3D view unavailable: $error');
    }
    _revision.value++;
  }

  /// Nothing to allocate up front: the engine's resources load when the view
  /// first mounts ([start]), so a boot that never visits Scene never touches
  /// the GPU.
  @override
  void init() {}

  @override
  void dispose() {
    _generation++;
    final graph = _graph;
    _graph = null;
    _agents = const [];
    _selection = null;
    _status = SceneViewStatus.idle;
    _started = null;
    _failure = null;
    if (graph == null) return;
    // `PhiEngine.stop` can run with the Scene still on screen (an OS close
    // stops the engine without tearing the tree down). Let a mounted view drop
    // the engine scene on its next build first, then free the scene — a
    // microtask runs after the current frame, never inside it.
    scheduleMicrotask(() {
      _revision.value++;
      graph.dispose();
    });
  }

  @override
  void setCamera(Camera camera) {
    orbit.reset(camera);
    _markDirty();
  }

  @override
  void setSelection(Vector3? worldPosition) {
    final current = _selection;
    if (current == null && worldPosition == null) return;
    if (current != null &&
        worldPosition != null &&
        current.x == worldPosition.x &&
        current.y == worldPosition.y &&
        current.z == worldPosition.z) {
      return;
    }
    _selection = worldPosition?.clone();
    _graph?.setSelection(_selection);
    _markDirty();
  }

  @override
  void installPicking(ScenePickHandler handler) => pointer.handler = handler;

  @override
  void setAgents(List<SceneAgent> agents) {
    _agents = List<SceneAgent>.unmodifiable(agents);
    _graph?.setAgents(_agents);
    _markDirty();
  }

  @override
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible && _dirtyWhileHidden) {
      _dirtyWhileHidden = false;
      _revision.value++;
    }
  }

  /// Ask the view to redraw: the camera moved under the pointer.
  void markCameraMoved() => _markDirty();

  void _markDirty() {
    if (!_visible) {
      _dirtyWhileHidden = true;
      return;
    }
    _revision.value++;
  }

  @override
  Widget buildView() => FlutterSceneView(renderer: this);
}
