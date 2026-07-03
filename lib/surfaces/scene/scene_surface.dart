import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../design/tokens/phi_colors.dart';
import '../../domain/scene/pick_ray.dart';
import '../../domain/scene/scene_agent.dart';
import '../../engine/bridge/camera.dart';
import '../../engine/bridge/scene_pick_handler.dart';
import '../../engine/bridge/scene_renderer.dart';
import '../../engine/engine.dart';
import '../surface.dart';

/// Phase 1 Scene surface — hosts the macbear-backed 3D viewport.
///
/// Seeds the renderer with one placeholder agent at the origin and an
/// initial orbit camera, then wires pointer picking + grab (issue #86): a
/// left-click picks the live agent under the cursor (selecting + grabbing it),
/// a drag pulls it, and a release throws or settles it — with misses, pan,
/// zoom, and keyboard navigation still handled by macbear's own orbit
/// controller. The screen→world unprojection lives in the engine bridge with
/// the live camera; this surface owns the selection and drives the field's
/// step from its own ticker so a grab pull is realized whether or not the
/// transport is running.
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
    return _SceneViewport(engine: engine, renderer: renderer);
  }
}

/// Inner widget that owns the one-shot seeding of camera + agents, the
/// pointer-picking wiring, and the field-stepping ticker.
///
/// Kept separate so the seed runs once on first mount, not on every Flutter
/// rebuild of the surrounding chrome.
class _SceneViewport extends StatefulWidget {
  const _SceneViewport({required this.engine, required this.renderer});

  final PhiEngine engine;
  final SceneRenderer renderer;

  @override
  State<_SceneViewport> createState() => _SceneViewportState();
}

class _SceneViewportState extends State<_SceneViewport>
    with SingleTickerProviderStateMixin
    implements ScenePickHandler {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  /// The key of the currently selected agent, or `null` when none is picked.
  /// While set, the ticker pushes this agent's live position to the renderer
  /// each frame so the highlight tracks it, and clears the halo when it
  /// despawns.
  int? _selectedKey;

  /// Whether a pointer grab is in flight. Kept so the ticker keeps running
  /// through a paused-transport drag (to realize the pull) even with nothing
  /// selected.
  bool _grabbing = false;

  @override
  void initState() {
    super.initState();
    widget.renderer.setCamera(
      Camera(position: Vector3(6, 6, 4), target: Vector3.zero()),
    );
    widget.renderer.setAgents([
      SceneAgent(position: Vector3.zero(), voiceIndex: 0),
    ]);
    // Route the viewport's pointer through our pick/grab handler; macbear's
    // orbit controller still runs for misses and non-left-button gestures.
    widget.renderer.installPicking(this);
    // The ticker only spins while a grab or selection is live; an idle Scene
    // schedules no frames (so it never blocks `pumpAndSettle`, and costs no GPU
    // when nothing is being manipulated).
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Each frame: advance the field from our own clock so a grab pull settles
  /// even with the transport paused (a no-op while playing — the playback tick
  /// already steps it), then keep the selection halo on the moving agent,
  /// dropping the selection once its agent despawns.
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds * 1e-6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    final midi = widget.engine.midiOrNull;
    midi?.stepFromSurface(dt);
    final key = _selectedKey;
    if (key != null) {
      final position = midi?.agentPosition(key);
      if (position == null) {
        _selectedKey = null; // its agent is gone
      }
      widget.renderer.setSelection(position);
    }
    _syncTicker();
  }

  /// Run the ticker exactly while there is per-frame work — a live grab or a
  /// live selection — and idle it otherwise.
  void _syncTicker() {
    final needed = _grabbing || _selectedKey != null;
    if (needed && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!needed && _ticker.isActive) {
      _ticker.stop();
    }
  }

  // --- ScenePickHandler: the pointer's bridge to the shared field ---

  @override
  int? pick(PickRay ray) => widget.engine.midiOrNull?.pick(ray);

  @override
  Vector3? agentPosition(int key) =>
      widget.engine.midiOrNull?.agentPosition(key);

  @override
  void grab(int key) {
    widget.engine.midiOrNull?.grab(key);
    _grabbing = true;
    _syncTicker();
  }

  @override
  void moveGrabTo(Vector3 target) =>
      widget.engine.midiOrNull?.moveGrabTo(target);

  @override
  void releaseGrab() {
    widget.engine.midiOrNull?.releaseGrab();
    _grabbing = false;
    _syncTicker();
  }

  @override
  void select(int? key) {
    _selectedKey = key;
    if (key == null) {
      widget.renderer.setSelection(null); // clear the halo immediately
    }
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.voidField,
      child: widget.renderer.buildView(),
    );
  }
}
