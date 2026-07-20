import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_radii.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/patcher/patch_cable_geometry.dart';
import '../../design/widgets/patcher/patch_canvas_constants.dart';
import '../../design/widgets/patcher/patch_grid_painter.dart';
import '../../domain/patcher/patch_cable.dart';
import '../../domain/patcher/patch_node.dart';
import '../../domain/patcher/patch_node_id.dart';
import '../../domain/patcher/patch_port.dart';
import '../../domain/patcher/patch_port_id.dart';
import '../../domain/patcher/patch_port_kind.dart';
import '../../engine/bridge/patch_object_descriptor.dart';
import '../../engine/state/patcher_controller.dart';
import 'patch_cable_colors.dart';
import 'patcher_cable_layer.dart';
import 'patcher_ghost_cable.dart';
import 'patcher_node_view.dart';

/// The pan/zoom canvas itself. Hosts the grid backdrop, the cable layer,
/// every [PatchNode]'s widget, and the in-flight ghost cable. Tracks the
/// cursor's scene position so the ghost cable can follow it.
///
/// Canvas interactions (design `docs/design/patcher.md` §6):
/// - **Body drag** moves the node (and the rest of the selection) as one
///   journaled step.
/// - **Cables** drag from an outlet; the ghost colours by the outlet's
///   `OutType`, compatible inlets light up, incompatible drops reject visibly.
///   Click a cable to select it.
/// - **Selection** — click a node, shift-click to extend, drag over empty
///   canvas to marquee. `Delete` removes the selection (nodes with their
///   cables, or the selected cable); `Ctrl+D` duplicates; `Ctrl+Z/Y` undo/redo.
///
/// Panning is a middle-mouse drag (the [InteractiveViewer]'s own pan is off so
/// a left-drag over empty canvas is free to marquee); scroll/pinch still zooms.
///
/// When [onCreateObject] is supplied the whole viewport is a drop target for a
/// palette entry: a dropped [PatchObjectDescriptor] resolves to the scene point
/// under the pointer and is reported back so the surface can create the object
/// there (design §5, drag-to-create).
class PatcherCanvas extends StatefulWidget {
  const PatcherCanvas({
    required this.controller,
    this.onCreateObject,
    this.onNodeTap,
    super.key,
  });

  final PatcherController controller;

  /// Called with a dropped palette entry and the scene point it landed on.
  /// Null disables drop-to-create.
  final void Function(PatchObjectDescriptor desc, Offset canvasPosition)?
  onCreateObject;

  /// Called when a node is tapped — drives the reference panel. Selection is
  /// handled by the canvas regardless.
  final void Function(PatchNode node)? onNodeTap;

  /// Key on the transient reject banner shown when a cable drop is incompatible.
  static const Key rejectKey = Key('PatcherCanvas.reject');

  @override
  State<PatcherCanvas> createState() => _PatcherCanvasState();
}

class _PatcherCanvasState extends State<PatcherCanvas> {
  final FocusNode _focus = FocusNode(debugLabel: 'patcher-canvas');

  Offset _cursor = Offset.zero;

  // Marquee / click press state, all in scene coordinates.
  Offset? _pressScene;
  Offset? _marqueeAnchor;
  bool _marqueeAdditive = false;
  bool _movedSincePress = false;
  Rect? _marquee;

  // Middle-mouse pan.
  bool _panning = false;

  // Transient reject cue for an incompatible cable drop.
  String? _reject;
  Timer? _rejectTimer;

  static const double _clickSlop = 4;

  PatcherController get _controller => widget.controller;

  @override
  void dispose() {
    _rejectTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Listener(
        // Opaque so empty scene areas (grid, gaps between nodes) still deliver
        // pointer events for marquee, panning and click-to-clear.
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerSignal: _onPointerSignal,
        onPointerHover: (e) => _updateCursor(e.localPosition),
        child: Stack(
          children: [
            // The scene is a plain transform host, not an InteractiveViewer:
            // the viewer's own scale recogniser would swallow node body-drags
            // and cable drags, so pan/zoom are driven directly instead —
            // middle-drag pans, the wheel zooms, a left-drag over empty canvas
            // marquees.
            Positioned.fill(
              child: ClipRect(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _controller.transform,
                    _controller.graph,
                  ]),
                  builder: (context, _) => Transform(
                    transform: _controller.transform.value,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: 0,
                      maxWidth: double.infinity,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: SizedBox(
                        width: PatchCanvasConstants.canvasSize,
                        height: PatchCanvasConstants.canvasSize,
                        child: _buildScene(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_reject != null)
              Positioned(
                key: PatcherCanvas.rejectKey,
                top: 10,
                left: 0,
                right: 0,
                child: Center(child: _RejectBanner(message: _reject!)),
              ),
          ],
        ),
      ),
    );

    final onCreate = widget.onCreateObject;
    if (onCreate == null) return viewport;
    return DragTarget<PatchObjectDescriptor>(
      onAcceptWithDetails: (details) =>
          onCreate(details.data, _toSceneFromGlobal(details.offset)),
      builder: (context, candidate, rejected) => viewport,
    );
  }

  Widget _buildScene() {
    final graph = _controller.graph;
    final positions = <PatchPortId, Offset>{};
    final voiceForSource = <PatchPortId, int>{};
    for (final n in graph.nodes) {
      positions.addAll(portPositionsFor(n));
      for (var i = 0; i < n.outputs.length; i++) {
        voiceForSource[PatchPortId(
              nodeId: n.id,
              side: PatchPortSide.output,
              index: i,
            )] =
            n.outputs[i].voice;
      }
    }
    final dragSource = graph.dragSourcePort;
    final compatibleInlets = dragSource == null
        ? const <PatchPortId>[]
        : _compatibleInlets(dragSource);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: PatchGridPainter())),
        ),
        Positioned.fill(
          child: PatcherCableLayer(
            cables: graph.cables,
            portPositions: positions,
            cableVoiceForSource: voiceForSource,
            selected: graph.selectedCable,
            version: graph.version,
          ),
        ),
        for (final n in graph.nodes)
          Positioned(
            left: n.position.dx,
            top: n.position.dy,
            width: n.size.width,
            height: n.size.height,
            child: PatcherNodeView(
              node: n,
              controller: _controller,
              onTap: () => _onNodeTap(n),
              selected: graph.isNodeSelected(n.id),
            ),
          ),
        for (final portId in compatibleInlets)
          if (positions[portId] != null)
            Positioned(
              left: positions[portId]!.dx - _highlightRadius,
              top: positions[portId]!.dy - _highlightRadius,
              width: _highlightRadius * 2,
              height: _highlightRadius * 2,
              child: const IgnorePointer(child: _InletHighlight()),
            ),
        if (dragSource != null)
          Positioned.fill(
            child: PatcherGhostCable(
              source: positions[dragSource] ?? Offset.zero,
              cursor: _cursor,
              color: patchOutletColor(_controller.outletTypeOf(dragSource)),
              glow: patchOutletGlow(_controller.outletTypeOf(dragSource)),
              kind: _kindForSource(dragSource),
            ),
          ),
        if (_marquee != null)
          Positioned.fromRect(
            rect: _marquee!,
            child: const IgnorePointer(child: _MarqueeBox()),
          ),
      ],
    );
  }

  static const double _highlightRadius = 9;

  // ─── keyboard ─────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (HardwareKeyboard.instance.isControlPressed) {
      switch (key) {
        case LogicalKeyboardKey.keyZ:
          HardwareKeyboard.instance.isShiftPressed
              ? _controller.redo()
              : _controller.undo();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyY:
          _controller.redo();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.keyD:
          _controller.duplicateSelection();
          return KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    }
    switch (key) {
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _controller.deleteSelection();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _controller.clearSelection();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ─── pointer ──────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kMiddleMouseButton) {
      _panning = true;
      return;
    }
    if (_controller.graph.dragSourcePort != null) return;

    final scene = _toScene(event.localPosition);
    // An outlet press starts a cable drag. Checked first so a port just past a
    // node's edge wins over the node itself.
    final port = _outputPortAt(scene);
    if (port != null) {
      setState(() => _cursor = scene);
      _controller.beginCableDrag(port);
      return;
    }
    // Presses that land on a node belong to the node's own gesture detector —
    // never a marquee.
    if (_nodeAt(scene) != null) {
      _pressScene = null;
      return;
    }
    // Empty canvas (or a cable): arm a marquee-or-click.
    _pressScene = scene;
    _marqueeAnchor = scene;
    _marqueeAdditive = HardwareKeyboard.instance.isShiftPressed;
    _movedSincePress = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_panning && event.buttons == kMiddleMouseButton) {
      _panBy(event.delta);
      return;
    }
    _updateCursor(event.localPosition);
    final press = _pressScene;
    if (press == null) return;
    final scene = _toScene(event.localPosition);
    if (!_movedSincePress && (scene - press).distance < _clickSlop) return;
    _movedSincePress = true;
    setState(() => _marquee = Rect.fromPoints(_marqueeAnchor!, scene));
  }

  void _onPointerUp(PointerUpEvent event) {
    // Take keyboard focus on release — *after* the enclosing pane's own
    // pointer-down focus grab, so the canvas keeps focus for Delete / Ctrl+D /
    // Ctrl+Z once a gesture completes (mirrors the piano roll's focus-on-gesture).
    _focus.requestFocus();
    if (_panning) {
      _panning = false;
      return;
    }
    final scene = _toScene(event.localPosition);

    // Finish an in-flight cable drag.
    final source = _controller.graph.dragSourcePort;
    if (source != null) {
      final target = _inputPortAt(scene);
      if (target != null && !_controller.connectViaGesture(source, target)) {
        _flashReject();
      }
      _controller.endCableDrag();
      return;
    }

    final press = _pressScene;
    _pressScene = null;
    if (press == null) return;

    if (_movedSincePress && _marquee != null) {
      _applyMarquee(_marquee!, additive: _marqueeAdditive);
      setState(() => _marquee = null);
      return;
    }
    // A click on empty canvas: pick a cable, or clear the selection.
    final cable = _cableAt(press);
    if (cable != null) {
      _controller.selectCable(cable);
    } else {
      _controller.clearSelection();
    }
  }

  void _onNodeTap(PatchNode node) {
    _focus.requestFocus();
    _controller.selectNode(
      node.id,
      additive: HardwareKeyboard.instance.isShiftPressed,
    );
    widget.onNodeTap?.call(node);
  }

  void _updateCursor(Offset local) {
    if (_controller.graph.dragSourcePort == null) return;
    setState(() => _cursor = _toScene(local));
  }

  // ─── selection helpers ──────────────────────────────────────────────────

  void _applyMarquee(Rect rect, {required bool additive}) {
    final hits = <PatchNodeId>{};
    for (final n in _controller.graph.nodes) {
      final r = Rect.fromLTWH(
        n.position.dx,
        n.position.dy,
        n.size.width,
        n.size.height,
      );
      if (r.overlaps(rect)) hits.add(n.id);
    }
    _controller.selectNodes(
      additive ? {..._controller.graph.selectedNodes, ...hits} : hits,
    );
  }

  List<PatchPortId> _compatibleInlets(PatchPortId source) {
    final out = <PatchPortId>[];
    for (final n in _controller.graph.nodes) {
      for (var i = 0; i < n.inputs.length; i++) {
        final id = PatchPortId(
          nodeId: n.id,
          side: PatchPortSide.input,
          index: i,
        );
        if (_controller.canConnect(source, id)) out.add(id);
      }
    }
    return out;
  }

  // ─── hit-testing (scene coordinates) ─────────────────────────────────────

  PatchNode? _nodeAt(Offset scene) {
    for (final n in _controller.graph.nodes) {
      final r = Rect.fromLTWH(
        n.position.dx,
        n.position.dy,
        n.size.width,
        n.size.height,
      ).inflate(PatchCanvasConstants.portHitRadius / 2);
      if (r.contains(scene)) return n;
    }
    return null;
  }

  PatchPortId? _inputPortAt(Offset scene) =>
      _portAt(scene, PatchPortSide.input);

  PatchPortId? _outputPortAt(Offset scene) =>
      _portAt(scene, PatchPortSide.output);

  PatchPortId? _portAt(Offset scene, PatchPortSide side) {
    const hitR = PatchCanvasConstants.portHitRadius;
    for (final n in _controller.graph.nodes) {
      final positions = portPositionsFor(n);
      final count = side == PatchPortSide.input
          ? n.inputs.length
          : n.outputs.length;
      for (var i = 0; i < count; i++) {
        final id = PatchPortId(nodeId: n.id, side: side, index: i);
        final pos = positions[id];
        if (pos == null) continue;
        if ((pos - scene).distance <= hitR) return id;
      }
    }
    return null;
  }

  PatchCable? _cableAt(Offset scene) {
    final positions = <PatchPortId, Offset>{};
    for (final n in _controller.graph.nodes) {
      positions.addAll(portPositionsFor(n));
    }
    PatchCable? best;
    var bestDistance = PatchCanvasConstants.cableHitThreshold;
    for (final c in _controller.graph.cables) {
      final a = positions[c.source];
      final b = positions[c.target];
      if (a == null || b == null) continue;
      final d = PatchCableGeometry.distanceTo(a, b, scene);
      if (d < bestDistance) {
        bestDistance = d;
        best = c;
      }
    }
    return best;
  }

  PatchPortKind _kindForSource(PatchPortId portId) {
    final node = _controller.graph.nodeById(portId.nodeId);
    if (node == null || portId.index >= node.outputs.length) {
      return PatchPortKind.control;
    }
    return node.outputs[portId.index].kind;
  }

  // ─── transforms ──────────────────────────────────────────────────────────

  Offset _toScene(Offset local) => _controller.transform.toScene(local);

  /// Convert a global drop point to scene coordinates, undoing the viewport
  /// offset and the live pan/zoom transform.
  Offset _toSceneFromGlobal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    return _toScene(local);
  }

  void _panBy(Offset delta) {
    final m = _controller.transform.value.clone();
    m[12] += delta.dx;
    m[13] += delta.dy;
    _controller.transform.value = m;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    _zoomBy(dy < 0 ? 1.1 : 1 / 1.1, event.localPosition);
  }

  /// Scale the view by [factor] about the viewport point [focal], clamped to
  /// the same range the [InteractiveViewer] would have enforced.
  void _zoomBy(double factor, Offset focal) {
    final scene = _toScene(focal);
    final current = _controller.transform.value;
    final scale = current.getMaxScaleOnAxis();
    final clamped = (scale * factor).clamp(0.25, 4.0);
    final applied = clamped / scale;
    if (applied == 1.0) return;
    _controller.transform.value = current.clone()
      ..translateByDouble(scene.dx, scene.dy, 0, 1)
      ..scaleByDouble(applied, applied, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
  }

  void _flashReject() {
    _rejectTimer?.cancel();
    setState(() => _reject = 'incompatible');
    _rejectTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _reject = null);
    });
  }
}

/// A ring drawn on a compatible inlet while a cable is being dragged.
class _InletHighlight extends StatelessWidget {
  const _InletHighlight();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: PhiColors.fg0, width: 1.5),
        boxShadow: const [BoxShadow(color: PhiColors.line2, blurRadius: 8)],
      ),
    );
  }
}

/// The rubber-band selection rectangle.
class _MarqueeBox extends StatelessWidget {
  const _MarqueeBox();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PhiColors.line1,
        border: Border.all(color: PhiColors.line2),
        borderRadius: PhiRadii.all1,
      ),
    );
  }
}

/// Transient banner shown when a cable is dropped on an incompatible inlet.
class _RejectBanner extends StatelessWidget {
  const _RejectBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: PhiColors.bg2,
        border: Border.all(color: PhiColors.hot.withValues(alpha: 0.6)),
        borderRadius: PhiRadii.all2,
      ),
      child: Text(
        'cable rejected · $message'.toUpperCase(),
        style: PhiType.caption().copyWith(color: PhiColors.hot),
      ),
    );
  }
}
