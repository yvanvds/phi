import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' as fs;

import '../../design/tokens/phi_colors.dart';
import 'flutter_scene_renderer.dart';
import 'scene_view_status.dart';

/// The Scene viewport widget [FlutterSceneRenderer.buildView] mounts.
///
/// Shows nothing while the engine loads, a notice when the 3D view is
/// unavailable, and otherwise the `flutter_scene` view under a pointer
/// [Listener] that feeds the renderer's [FlutterSceneRenderer.pointer]. The
/// view redraws on demand — whenever the renderer's
/// [FlutterSceneRenderer.changes] ticks or the pointer moves the camera — so
/// an idle Scene schedules no frames.
class FlutterSceneView extends StatefulWidget {
  const FlutterSceneView({required this.renderer, super.key});

  final FlutterSceneRenderer renderer;

  /// Key of the [RepaintBoundary] wrapping the drawn 3D view, for tests that
  /// read its pixels back.
  static const Key viewportKey = Key('scene-3d-viewport');

  /// Key of the unavailable notice.
  static const Key unavailableKey = Key('scene-unavailable-notice');

  @override
  State<FlutterSceneView> createState() => _FlutterSceneViewState();
}

class _FlutterSceneViewState extends State<FlutterSceneView> {
  Size _viewport = Size.zero;

  FlutterSceneRenderer get _renderer => widget.renderer;

  @override
  void initState() {
    super.initState();
    _renderer.changes.addListener(_onChanged);
    // `PhiEngine.start` normally started it already; a no-op then.
    _renderer.start();
  }

  @override
  void didUpdateWidget(FlutterSceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.renderer, widget.renderer)) {
      oldWidget.renderer.changes.removeListener(_onChanged);
      widget.renderer.changes.addListener(_onChanged);
      widget.renderer.start();
    }
  }

  @override
  void dispose() {
    _renderer.changes.removeListener(_onChanged);
    // A grab must not outlive the view that started it.
    _renderer.pointer.cancelAll();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // The surface seeds the camera and agents from its own `initState`, which
    // can land mid-build; rebuild after that frame rather than inside it.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  void _onCameraMoved(bool moved) {
    if (moved) _renderer.markCameraMoved();
  }

  @override
  Widget build(BuildContext context) {
    switch (_renderer.status) {
      case SceneViewStatus.idle:
      case SceneViewStatus.starting:
        return const SizedBox.expand();
      case SceneViewStatus.unavailable:
        return _buildUnavailable();
      case SceneViewStatus.ready:
        return _buildViewport();
    }
  }

  Widget _buildViewport() {
    final graph = _renderer.graph!;
    final pointer = _renderer.pointer;
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => pointer.pointerDown(
            e.pointer,
            e.localPosition,
            e.buttons,
            _viewport,
          ),
          onPointerMove: (e) => _onCameraMoved(
            pointer.pointerMove(
              e.pointer,
              e.localPosition,
              e.localDelta,
              _viewport,
            ),
          ),
          onPointerUp: (e) => pointer.pointerUp(e.pointer),
          onPointerCancel: (e) => pointer.pointerCancel(e.pointer),
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _onCameraMoved(pointer.scroll(e.scrollDelta.dy));
            }
          },
          child: RepaintBoundary(
            key: FlutterSceneView.viewportKey,
            child: fs.SceneView(
              graph.scene,
              camera: _renderer.engineCamera,
              autoTick: false,
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnavailable() {
    return const ColoredBox(
      color: PhiColors.bg0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              FlutterSceneRenderer.unavailableNotice,
              key: FlutterSceneView.unavailableKey,
              style: TextStyle(color: PhiColors.fg2),
            ),
            SizedBox(height: 6),
            Text(
              FlutterSceneRenderer.unavailableDetail,
              style: TextStyle(color: PhiColors.fg3, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
