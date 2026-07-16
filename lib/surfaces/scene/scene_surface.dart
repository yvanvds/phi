import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/widgets/toggle/phi_toggle.dart';
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
/// the live camera; this surface owns the selection and tracks the halo on the
/// moving agent from its own ticker. Field motion itself is stepped by the
/// player's frame ticker in all cases (issue #103) — a grab starts it even on a
/// stopped transport — so this surface no longer steps the field.
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

  /// Whether the pick-friendly dev demo (issue #90) is currently loaded. The
  /// overlay toggle drives this; loading seeds a handful of long-lived,
  /// well-separated agents into the shared field so pick / select / grab can
  /// be exercised by hand without waiting on short, clustered playback spawns.
  bool _demoLoaded = false;

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

  /// Each frame while a grab or selection is live: keep the selection halo on
  /// the moving agent, dropping the selection once its agent despawns. The
  /// field's own motion is stepped by the player's frame ticker in all cases
  /// now (issue #103) — a grab starts it even on a stopped transport — so this
  /// ticker only reads positions to track the halo, it no longer steps the
  /// field.
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds * 1e-6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;
    final midi = widget.engine.midiOrNull;
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

  /// Load or drop the pick-friendly dev demo (issue #90). Loading pushes a
  /// spread of long-lived agents into the shared field via the MIDI player;
  /// dropping clears them and any selection halo riding one of them.
  void _toggleDemo(bool load) {
    final midi = widget.engine.midiOrNull;
    if (midi == null) return;
    setState(() => _demoLoaded = load);
    if (load) {
      midi.loadSceneDemo();
    } else {
      _selectedKey = null;
      widget.renderer.setSelection(null);
      midi.clearSceneDemo();
      _syncTicker();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PhiColors.voidField,
      child: Stack(
        children: [
          Positioned.fill(child: widget.renderer.buildView()),
          // Dev-only aid: a toggle that seeds a pick-friendly agent set so the
          // pointer path can be exercised by hand. Hidden in release builds.
          if (kDebugMode && widget.engine.midiOrNull != null)
            Positioned(top: 12, left: 12, child: _buildDemoToggle()),
        ],
      ),
    );
  }

  Widget _buildDemoToggle() {
    return Container(
      key: const Key('scene-pick-demo-toggle'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PhiColors.bg1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PhiColors.line1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PICK DEMO',
            style: TextStyle(
              color: PhiColors.fg2,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          PhiToggle(value: _demoLoaded, onChanged: _toggleDemo),
        ],
      ),
    );
  }
}
