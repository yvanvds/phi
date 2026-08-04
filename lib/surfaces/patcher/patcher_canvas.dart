import 'dart:async';
import 'dart:math' as math;

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
import '../../engine/state/node_type_registry.dart';
import '../../engine/state/patcher_controller.dart';
import 'create/patch_inline_object_box.dart';
import 'patch_cable_colors.dart';
import 'patcher_cable_layer.dart';
import 'patcher_ghost_cable.dart';
import 'patcher_node_view.dart';

/// The pan/zoom canvas itself. Hosts the grid backdrop, the cable layer,
/// every [PatchNode]'s widget, and the in-flight ghost cable. Tracks the
/// cursor's scene position so the ghost cable can follow it.
///
/// Every scene gesture — marquee, cable drag, node drag, select and
/// double-click — is driven from this one raw [Listener] rather than from
/// recognisers on the nodes themselves. A `GestureDetector.onPan` only accepts
/// after ~18px of movement and then *discards* that distance, so a dragged node
/// lagged the pointer and short drags did nothing at all (issue #352); reading
/// the pointer directly and measuring scene-space deltas from the press point
/// keeps the node glued to the cursor at any zoom.
///
/// The flip side of owning the raw stream is owning its cancellation: a gesture
/// whose pointer is torn away never gets its pointer-up, so every transient it
/// armed is dropped wholesale in `_resetGesture` (issue #355). New gesture
/// state belongs there as well as where it is set.
///
/// Canvas interactions (design `docs/design/patcher.md` §6):
/// - **Body drag** moves the node (and the rest of the selection) as one
///   journaled step.
/// - **Cables** drag from *either* end — an outlet forwards or an inlet
///   backwards (issue #359); the ghost colours by the anchored port's type,
///   compatible ports on the opposite side light up, incompatible drops reject
///   visibly. Click a cable to select it; grab one near an endpoint and drag to
///   detach and re-route it, or drop it on nothing to delete it. Every outcome
///   is one journaled step.
/// - **Selection** — click a node, shift-click to extend, drag over empty
///   canvas to marquee. `Delete` removes the selection (nodes with their
///   cables, or the selected cable); `Ctrl+D` duplicates; `Ctrl+Z/Y` undo/redo.
/// - **Arrow keys nudge** the selected nodes by one grid cell, `Shift` by a
///   major cell (issue #368). A held arrow moves live on every repeat but
///   journals **once**, on release, so `Ctrl+Z` undoes the burst rather than
///   one repeat of it.
/// - **Right-click a node** opens its context menu — the same verbs, named, for
///   anyone who does not already know the shortcuts (issue #356).
/// - **View navigation** — middle-drag or `Space`-hold + left-drag pans, the
///   wheel zooms about the pointer, `Ctrl+0` frames the whole patch (#369).
/// - **Cursor + hover** teach the hit zones the canvas would otherwise keep to
///   itself (issue #359): a move cursor over draggable node chrome, a crosshair
///   plus a ring over a port, a pointer over a cable. The whole viewport is one
///   [MouseRegion] fed by the same scene-space hit-tests the presses use, so
///   what the cursor promises and what a press does can never drift apart.
///
/// Panning is a middle-mouse drag, or **hold `Space` and left-drag** for the
/// mice that have no third button (issue #369) — the [InteractiveViewer]'s own
/// pan is off so a plain left-drag over empty canvas is free to marquee;
/// scroll/pinch still zooms. **`Ctrl+0` frames the patch**: it fits every node
/// into the viewport (never magnifying past 1:1) and centres them, which on an
/// empty canvas is simply the identity view.
///
/// When [onCreateObject] is supplied the whole viewport is a drop target for a
/// palette entry: a dropped [PatchObjectDescriptor] resolves to the scene point
/// under the pointer and is reported back so the surface can create the object
/// there (design §5, drag-to-create). Supply [objectTypes] as well and a
/// **double-click on empty canvas** opens the inline object box at that scene
/// point — the same callback, with the arguments typed into the box (issue
/// #358).
class PatcherCanvas extends StatefulWidget {
  const PatcherCanvas({
    required this.controller,
    this.objectTypes = const [],
    this.snapToGrid = false,
    this.onCreateObject,
    this.onNodeTap,
    this.onNodeDoubleTap,
    this.onNodeContextMenu,
    super.key,
  });

  final PatcherController controller;

  /// Whether a node **drop** — the release of a body drag, or the release of an
  /// arrow-key nudge — lands the moved set on the canvas's minor grid (issue
  /// #368). Off by default: the patcher free-places, and the discipline is
  /// something the user turns on from the placement bar.
  final bool snapToGrid;

  /// The engine's object catalogue, for the inline object box's completion.
  /// Empty disables inline creation — a double-click on empty canvas then does
  /// nothing, since there is nothing to complete against.
  final List<PatchObjectDescriptor> objectTypes;

  /// Called with a catalogue entry and the scene point to create it at — a
  /// palette entry dropped on the canvas, or the object the inline box's Enter
  /// resolved. `args` is the checked creation-argument string from the box;
  /// null (the drop path) means "the type's documented defaults". Null disables
  /// both create gestures.
  final void Function(
    PatchObjectDescriptor desc,
    Offset canvasPosition, {
    String? args,
  })?
  onCreateObject;

  /// Called when a node is tapped — drives the reference panel. Selection is
  /// handled by the canvas regardless.
  final void Function(PatchNode node)? onNodeTap;

  /// Called when a node is double-clicked — opens the metadata params dialog
  /// for a non-GUI node (design §7). Detected from raw pointer timing so it
  /// never adds a disambiguation delay to the node's own single-tap select.
  final void Function(PatchNode node)? onNodeDoubleTap;

  /// Called on a **right-click** over a node, with the node and the global
  /// pointer position — the surface opens the node's context menu there
  /// (`edit parameters…` / duplicate / delete, issue #356). Null disables it.
  ///
  /// The secondary button is read from this canvas's own [Listener] rather than
  /// from a `GestureDetector.onSecondaryTapDown` on the node: a recogniser here
  /// would sit in the arena against the primary-button gestures the canvas
  /// already owns, which is exactly the competition issue #352 removed.
  final void Function(PatchNode node, Offset globalPosition)? onNodeContextMenu;

  /// Key on the transient reject banner shown when a cable drop is incompatible.
  static const Key rejectKey = Key('PatcherCanvas.reject');

  /// Key on the rubber-band selection rectangle — present only while a marquee
  /// is actually being dragged, so its absence is assertable (issue #355).
  static const Key marqueeKey = Key('PatcherCanvas.marquee');

  /// Key on the inline object box — present only while one is open (issue #358).
  static const Key inlineCreateKey = Key('PatcherCanvas.inlineCreate');

  /// Key on the ring drawn around the port under the pointer — present only
  /// while one is actually hovered, so its absence is assertable (issue #359).
  static const Key portHoverKey = Key('PatcherCanvas.portHover');

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

  // Node press / drag state, all in scene coordinates. `_nodePressScene` is
  // where the press landed (the slop reference); `_nodeDragScene` is the last
  // point already applied, so the delta fed to the controller covers the slop
  // distance too — the node never falls behind the pointer.
  PatchNodeId? _pressNode;
  Offset _nodePressScene = Offset.zero;
  Offset _nodeDragScene = Offset.zero;
  bool _draggingNode = false;

  // Whether the press currently in flight landed on a body that runs its own
  // gestures. Such a press belongs to the widget underneath, so the canvas
  // neither drags the node nor claims keyboard focus on release — an editable
  // body (a `.i`/`.f` number field) has just taken focus for its caret and must
  // keep it (issue #353).
  bool _pressOnInteractiveBody = false;

  // Cable-endpoint grab (issue #359). Armed by a press near one end of an
  // existing cable and only *detached* once the pointer clears `_clickSlop`, so
  // a press that never moves is still the click that selects the cable.
  // `_pressCableAnchor` is the end that stays put — the far end from the grab.
  PatchCable? _pressCable;
  PatchPortId? _pressCableAnchor;
  Offset _pressCableScene = Offset.zero;

  // Hover affordance (issue #359). Recomputed from the same scene-space
  // hit-tests the presses use, but only committed when it actually *changes* —
  // sweeping the pointer across empty canvas must not rebuild the scene at the
  // pointer's report rate.
  MouseCursor _hoverCursor = SystemMouseCursors.basic;
  PatchPortId? _hoverPort;

  // Middle-mouse pan — and, since issue #369, the space-hold pan too: both end
  // up here, because from the pointer's side they are the same gesture.
  bool _panning = false;

  // Space-hold pan (issue #369). `_spaceHeld` records that the space key went
  // down *on this canvas*, i.e. while it held the keyboard itself; whether the
  // key is still down is asked of `HardwareKeyboard` instead — see
  // `_spaceStillHeld`, which is what every read goes through. `_spacePan` says
  // the pan currently in flight is the one space armed, so a space release can
  // end that pan without touching a middle-drag that happens to be running.
  bool _spaceHeld = false;
  bool _spacePan = false;

  // Where the pointer last hovered, in viewport pixels — the point the cursor
  // is re-resolved against when something other than a pointer move changes
  // what the canvas would do there (space taken or released). Null until a
  // mouse has actually been over the viewport.
  Offset? _hoverLocal;

  // Keyboard nudge (issue #368). A held arrow delivers a `KeyDownEvent` and
  // then a stream of `KeyRepeatEvent`s: every one of them moves the selection
  // live, but the move is journaled only when the key comes back **up**, so a
  // burst is one undo step instead of one per repeat — which is what would make
  // `Ctrl+Z` useless on a canvas nudged into place.
  //
  // True exactly while such a burst is open, i.e. while the controller is
  // holding drag origins that no release has committed yet.
  bool _nudging = false;

  // Double-tap tracking (raw pointer timing, so single-tap select stays
  // instant — a nested GestureDetector.onDoubleTap would delay it). Only a
  // *movement-free* press is recorded, and both presses of the pair must be
  // movement-free, so click-to-select followed by a drag is never mistaken
  // for a double-click (issue #352).
  //
  // The same pairing serves *empty* canvas, where it opens the inline object
  // box (issue #358). A node pair matches by identity; an empty-canvas pair has
  // no identity to match, so it matches by proximity instead and remembers
  // where the first click landed, in **viewport** pixels — the space
  // `kDoubleTapSlop` is expressed in, and the only one whose meaning survives a
  // zoom.
  PatchNodeId? _lastTapNode;
  bool _lastTapOnEmpty = false;
  Offset _lastTapLocal = Offset.zero;
  Duration _lastTapAt = Duration.zero;

  // Scene point of the open inline object box, or null when none is open.
  Offset? _inlineCreateAt;
  final GlobalKey _inlineBoxKey = GlobalKey();

  // Transient reject cue for an incompatible cable drop.
  String? _reject;
  Timer? _rejectTimer;

  static const double _clickSlop = 4;

  /// Zoom range the view is held inside, however it got there — the wheel, a
  /// pinch, or the `Ctrl+0` fit.
  static const double _minScale = 0.25;
  static const double _maxScale = 4;

  /// Scene-space breathing room left around the graph by the `Ctrl+0` fit, so
  /// the outermost nodes do not end up flush against the viewport edge.
  static const double _fitPadding = 40;

  PatcherController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // A nudge burst is ended by the arrow's key-up — which never arrives if the
    // keyboard leaves mid-burst (a dialog opens over the canvas, the pane is
    // switched). Committing on focus loss is what keeps that move on the undo
    // stack instead of stranding it as an unjournaled edit; the same listener
    // disarms a held space for the same reason (issue #369).
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _rejectTimer?.cancel();
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _commitNudge();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      // One region for the whole viewport rather than a cursor per node: the
      // things worth pointing at (ports, cables, the draggable part of a node)
      // are hit-tested in *scene* space by this canvas alone, and a widget-level
      // cursor could only ever guess at them (issue #359). A body that owns its
      // own gestures still sets its own cursor — it sits deeper, so it wins.
      child: MouseRegion(
        cursor: _hoverCursor,
        onExit: (_) => _setHover(SystemMouseCursors.basic, null),
        child: Listener(
          // Opaque so empty scene areas (grid, gaps between nodes) still deliver
          // pointer events for marquee, panning and click-to-clear.
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: _onPointerSignal,
          onPointerHover: _onPointerHover,
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
    final positions = _portPositions;
    final voiceForSource = <PatchPortId, int>{};
    for (final n in graph.nodes) {
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
    final compatiblePorts = dragSource == null
        ? const <PatchPortId>[]
        : _compatiblePorts(dragSource);
    final hoverCentre = dragSource == null ? positions[_hoverPort] : null;

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
              selected: graph.isNodeSelected(n.id),
            ),
          ),
        // The port under the pointer, ringed so the (otherwise invisible) hit
        // zone is learnable. Suppressed mid-drag, where the compatible-port
        // highlight below is saying something more useful (issue #359).
        if (hoverCentre != null)
          Positioned(
            key: PatcherCanvas.portHoverKey,
            left: hoverCentre.dx - _hoverRadius,
            top: hoverCentre.dy - _hoverRadius,
            width: _hoverRadius * 2,
            height: _hoverRadius * 2,
            child: const IgnorePointer(child: _PortHoverRing()),
          ),
        for (final portId in compatiblePorts)
          if (positions[portId] != null)
            Positioned(
              left: positions[portId]!.dx - _highlightRadius,
              top: positions[portId]!.dy - _highlightRadius,
              width: _highlightRadius * 2,
              height: _highlightRadius * 2,
              child: const IgnorePointer(child: _PortHighlight()),
            ),
        if (dragSource != null)
          Positioned.fill(
            child: PatcherGhostCable(
              source: positions[dragSource] ?? Offset.zero,
              cursor: _cursor,
              color: patchOutletColor(_ghostTypeFor(dragSource)),
              glow: patchOutletGlow(_ghostTypeFor(dragSource)),
              kind: _kindForAnchor(dragSource),
              backwards: dragSource.side == PatchPortSide.input,
            ),
          ),
        if (_marquee != null)
          Positioned.fromRect(
            key: PatcherCanvas.marqueeKey,
            rect: _marquee!,
            child: const IgnorePointer(child: _MarqueeBox()),
          ),
        // The box lives *in the scene*, at the point that was double-clicked,
        // so it sits where the object it is about to make will — and pans and
        // zooms with everything else rather than floating over it. Last child,
        // so its completion list covers the nodes it overlaps.
        if (_inlineCreateAt != null)
          Positioned(
            key: PatcherCanvas.inlineCreateKey,
            left: _inlineCreateAt!.dx,
            top: _inlineCreateAt!.dy,
            child: PatchInlineObjectBox(
              key: _inlineBoxKey,
              objectTypes: widget.objectTypes,
              onCreate: _createInline,
              onDismiss: _closeInlineCreate,
            ),
          ),
      ],
    );
  }

  static const double _highlightRadius = 9;

  /// Radius of the hover ring — a shade tighter than [_highlightRadius] so a
  /// port that is both hovered *and* compatible reads as two rings, not one
  /// thick one.
  static const double _hoverRadius = 8;

  // ─── keyboard ─────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // The canvas shortcuts belong to the canvas alone. This [Focus] is an
    // *ancestor* of every node body's focus node, so a key pressed while a
    // `.i`/`.f` number field is being edited arrives here first — ahead of
    // Flutter's own `DefaultTextEditingShortcuts`, which sit above the surface.
    // Without this guard Backspace would delete the selected nodes instead of a
    // character, and the box could never be typed into (issue #353).
    if (!_focus.hasPrimaryFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // The release of an arrow closes the nudge burst it opened, journaling the
    // whole run as one move (issue #368). Read before the down/repeat filter
    // below, which is the only key event this canvas otherwise cares about.
    if (event is KeyUpEvent) {
      // Letting go of space disarms the pan and ends one already in flight
      // (issue #369) — a pan the pointer is still dragging must not outlive the
      // key that armed it.
      if (key == LogicalKeyboardKey.space) {
        _releaseSpace();
        return KeyEventResult.handled;
      }
      if (_nudgeStep(key) == null) return KeyEventResult.ignored;
      _commitNudge();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      // `Ctrl+0` frames the patch (issue #369). Matched before the switch
      // because it is read off the **physical** key as well as the logical one:
      // on an AZERTY keyboard the digit row is shifted, so the key in the `0`
      // position reports `à` unshifted and `0` only with Shift — and requiring
      // either glyph would make the shortcut unreachable on half the layouts
      // this is used on. Digit *positions* are common to QWERTY, AZERTY and
      // QWERTZ, which is exactly why the physical key is the honest question
      // here (letters, where positions differ, stay logical — see `_nudgeStep`).
      if (_isResetViewKey(event)) {
        _resetView();
        return KeyEventResult.handled;
      }
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
    // Holding space arms the pan (issue #369) — the habit every canvas app
    // shares, and the one that does not need a three-button mouse. Repeats are
    // idempotent: the key is a *mode*, not an action. Handled either way so the
    // space never reaches anything above as a keypress of its own.
    if (key == LogicalKeyboardKey.space) {
      _armSpace();
      return KeyEventResult.handled;
    }
    final step = _nudgeStep(key);
    if (step != null) return _nudge(step);
    switch (key) {
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _controller.deleteSelection();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _commitNudge();
        _controller.clearSelection();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// The scene-space move an arrow [key] asks for, or null for anything else.
  ///
  /// One grid cell, or a major cell with `Shift` — the same lattice the grid
  /// backdrop paints, so a nudged node stays on the dots it started on. Arrows
  /// are read as **logical** keys, which is what keeps this working on a layout
  /// that is not QWERTY: unlike a letter, an arrow means the same thing on
  /// every keyboard, and asking for the physical key would be asking about a
  /// position rather than the key the user actually pressed.
  Offset? _nudgeStep(LogicalKeyboardKey key) {
    final d = HardwareKeyboard.instance.isShiftPressed
        ? PatchCanvasConstants.gridMajor
        : PatchCanvasConstants.gridCell;
    switch (key) {
      case LogicalKeyboardKey.arrowLeft:
        return Offset(-d, 0);
      case LogicalKeyboardKey.arrowRight:
        return Offset(d, 0);
      case LogicalKeyboardKey.arrowUp:
        return Offset(0, -d);
      case LogicalKeyboardKey.arrowDown:
        return Offset(0, d);
      default:
        return null;
    }
  }

  /// Move the selected nodes by [step], opening a burst on the first press and
  /// adding to it on every repeat (issue #368).
  ///
  /// Deliberately the *same* machinery a body drag uses — origins captured
  /// once, live preview per event, one [MovePatchNodesCommand] at the end — so
  /// a nudge and a drag are the same edit as far as the journal, the engine's
  /// GUI properties and the grid snap are concerned.
  ///
  /// Nothing selected means nothing to move, and the arrow is left unhandled so
  /// it can go on to mean something else somewhere else.
  KeyEventResult _nudge(Offset step) {
    if (_controller.graph.selectedNodes.isEmpty) return KeyEventResult.ignored;
    if (!_nudging) {
      _nudging = true;
      _controller.beginSelectionMove();
    }
    _controller.dragSelectedBy(step);
    return KeyEventResult.handled;
  }

  /// Close an open nudge burst, journaling the whole run as one move. A no-op
  /// when no burst is open, so it is safe to call from every path that ends one
  /// — the key-up, a press that starts another gesture, and losing the keyboard.
  void _commitNudge() {
    if (!_nudging) return;
    _nudging = false;
    _controller.endNodeDrag(snapToGrid: widget.snapToGrid);
  }

  // ─── space-hold pan + reset view (issue #369) ─────────────────────────

  /// Arm the space pan and say so with the cursor. A no-op once armed, so the
  /// auto-repeat stream a held key produces costs nothing.
  void _armSpace() {
    if (_spaceHeld) return;
    _spaceHeld = true;
    _showSpaceCursor();
  }

  /// Disarm the space pan on the canvas's own key-up, ending one already in
  /// flight.
  void _releaseSpace() {
    if (!_spaceHeld) return;
    _spaceHeld = false;
    _endSpacePan();
    _restoreCursor();
  }

  /// Whether the space pan is armed **right now**.
  ///
  /// Two things have to hold. This canvas must have seen the space go down
  /// while it held the keyboard itself, so a space typed into a `.i`/`.f` box
  /// or the inline create box is never a pan (issue #353's rule). And the key
  /// must still be down.
  ///
  /// That second half is read from [HardwareKeyboard] rather than trusted to a
  /// key-up arriving here, because in the real shell it often does not: the
  /// enclosing pane grabs the keyboard on *every* pointer-down, so the release
  /// of a space held through a drag lands there and not on this node. Asking
  /// the hardware what is down is the one answer no focus change can
  /// invalidate — and it is what stops a held space from leaving a pan-armed
  /// canvas behind it, where the next left-drag would pan instead of marquee
  /// with nothing on screen to explain why.
  bool _spaceStillHeld() {
    if (!_spaceHeld) return false;
    if (HardwareKeyboard.instance.logicalKeysPressed.contains(
      LogicalKeyboardKey.space,
    )) {
      return true;
    }
    _spaceHeld = false;
    return false;
  }

  /// End a pan that space armed, leaving a middle-drag pan alone. The pointer
  /// may well still be down: from here the drag moves nothing and its release
  /// is just a release, which is what keeps a space let go mid-drag from
  /// stranding a pan.
  void _endSpacePan() {
    if (!_spacePan) return;
    _spacePan = false;
    _panning = false;
  }

  /// The pan cursor for the current state — open hand while merely armed,
  /// closed while actually dragging the scene.
  void _showSpaceCursor() => _setHover(
    _spacePan ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
    null,
  );

  /// Re-resolve the cursor for wherever the pointer was last seen, after
  /// something that is not a pointer move changed the answer. Falls back to the
  /// plain cursor when no mouse has been over the viewport at all.
  void _restoreCursor() {
    final local = _hoverLocal;
    if (local == null) {
      _setHover(SystemMouseCursors.basic, null);
      return;
    }
    _applyHover(local);
  }

  /// Whether [event] is the `Ctrl+0` that frames the patch.
  ///
  /// The physical key is authoritative and the logical one is accepted as well,
  /// so the shortcut answers to the key in the `0` position on every layout
  /// *and* to whatever a platform reports for a numpad zero.
  bool _isResetViewKey(KeyEvent event) =>
      event.physicalKey == PhysicalKeyboardKey.digit0 ||
      event.physicalKey == PhysicalKeyboardKey.numpad0 ||
      event.logicalKey == LogicalKeyboardKey.digit0 ||
      event.logicalKey == LogicalKeyboardKey.numpad0;

  /// Bring the whole patch back into view (`Ctrl+0`, issue #369).
  ///
  /// The issue left the choice between "reset to 1:1" and "zoom to fit" open.
  /// Fit wins, because the failure it rescues is *being lost*: a pan that ran
  /// off the 4000px canvas leaves nothing on screen, and a reset to the origin
  /// only helps when the patch happens to live there. Framing everything is the
  /// one answer that is right from anywhere — and it degrades to exactly the
  /// identity view when there is nothing to frame, which is the reset.
  ///
  /// Never magnifies past 1:1: a two-node patch blown up to fill the viewport
  /// would be a worse view than the one it replaced.
  void _resetView() {
    final bounds = _graphBounds();
    final viewport = (context.findRenderObject() as RenderBox?)?.size;
    if (bounds == null || viewport == null || viewport.isEmpty) {
      _controller.transform.value = Matrix4.identity();
      return;
    }
    final padded = bounds.inflate(_fitPadding);
    final scale = math
        .min(
          1.0,
          math.min(
            viewport.width / padded.width,
            viewport.height / padded.height,
          ),
        )
        .clamp(_minScale, _maxScale)
        .toDouble();
    _controller.transform.value = Matrix4.identity()
      ..translateByDouble(
        viewport.width / 2 - padded.center.dx * scale,
        viewport.height / 2 - padded.center.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// The scene-space rectangle every node fits inside, or null when the graph
  /// is empty.
  Rect? _graphBounds() {
    Rect? bounds;
    for (final n in _controller.graph.nodes) {
      final r = Rect.fromLTWH(
        n.position.dx,
        n.position.dy,
        n.size.width,
        n.size.height,
      );
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    return bounds;
  }

  // ─── pointer ──────────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    // A press is a new gesture, so whatever the keyboard was still holding is
    // finished here: a nudge burst left open would otherwise have its origins
    // overwritten by the drag this press is about to start, and its move would
    // never reach the journal (issue #368).
    _commitNudge();
    _pressOnInteractiveBody = false;
    if (_inlineCreateAt != null) {
      // A press inside the open inline object box belongs to its field — the
      // same rule an editable node body gets (issue #353): the canvas starts no
      // gesture here and does not take the keyboard back on release, so the
      // caret lands where it was clicked.
      if (_pressInsideInlineBox(event.position)) {
        _pressOnInteractiveBody = true;
        return;
      }
      // A press anywhere else abandons the box, exactly as Escape does — the
      // canvas is left untouched — and the press itself goes on to do whatever
      // it would have done.
      _closeInlineCreate();
    }
    if (event.buttons == kMiddleMouseButton) {
      _panning = true;
      return;
    }
    // Space held: a left-press pans instead of doing whatever it landed on
    // (issue #369). Checked ahead of every scene hit-test, because the whole
    // point of the mode is that it overrides them — a press over a node or a
    // port has to pan just the same, or the gesture would only work on the
    // empty patches that least need it.
    if (_spaceStillHeld() && event.buttons == kPrimaryMouseButton) {
      _panning = true;
      _spacePan = true;
      _showSpaceCursor();
      return;
    }
    if (_controller.graph.dragSourcePort != null) return;

    if (event.buttons == kSecondaryMouseButton) {
      _onSecondaryPress(event.position, _toScene(event.localPosition));
      return;
    }

    final scene = _toScene(event.localPosition);
    // A press on a **port of either side** starts a cable drag: from an outlet
    // forwards, from an inlet backwards, Max-style (issue #359). Checked first
    // so a port just past a node's edge wins over the node itself; the press
    // radius is tight enough (portPressRadius) that the zone never reaches the
    // header or the bulk of the body, which stay node-drag territory.
    final port = _portPressAt(scene);
    if (port != null) {
      setState(() => _cursor = scene);
      _setHover(SystemMouseCursors.precise, null);
      _controller.beginCableDrag(port);
      return;
    }
    // Just off a port, along an existing cable: arm a re-route of that cable.
    // Only *armed* here — the detach waits for the pointer to clear the click
    // slop, so a click near an endpoint still selects the cable it is on.
    final grab = _cableEndAt(scene);
    if (grab != null) {
      _pressCable = grab.cable;
      _pressCableAnchor = grab.anchor;
      _pressCableScene = scene;
      return;
    }
    final node = _nodeAt(scene);
    if (node != null) {
      // A live GUI body owns its own gestures and sits deeper in the tree:
      // leave the press to it entirely, so operating a control neither drags
      // nor re-selects its node. Such nodes are dragged by the header.
      if (_onInteractiveBody(node, scene)) {
        _pressOnInteractiveBody = true;
        return;
      }
      // Arm a node drag-or-click. The drag itself only starts once the pointer
      // clears `_clickSlop`, so a plain click still selects.
      _pressNode = node.id;
      _nodePressScene = scene;
      _nodeDragScene = scene;
      _draggingNode = false;
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
    // Whichever button armed it — middle, or left with space down (issue #369)
    // — a pan in flight owns the pointer until its release. The button is not
    // re-checked: `_panning` is only ever true between the press that armed it
    // and the release, cancel or space-up that clears it.
    if (_panning) {
      // A space pan is only ever as alive as the key that armed it, and the
      // release may well have landed elsewhere — the pane took the keyboard on
      // this very press — so it is re-read here rather than waited for.
      if (_spacePan && !_spaceStillHeld()) {
        _endSpacePan();
        _applyHover(event.localPosition);
        return;
      }
      _panBy(event.delta);
      return;
    }
    _trackGhost(event.localPosition);
    if (_pressCable != null) {
      _moveCableGrab(_toScene(event.localPosition));
      return;
    }
    if (_pressNode != null) {
      _moveNodeDrag(_toScene(event.localPosition));
      return;
    }
    final press = _pressScene;
    if (press == null) return;
    final scene = _toScene(event.localPosition);
    if (!_movedSincePress && (scene - press).distance < _clickSlop) return;
    _movedSincePress = true;
    setState(() => _marquee = Rect.fromPoints(_marqueeAnchor!, scene));
  }

  /// Detach the grabbed cable (on the first move past [_clickSlop]) and then
  /// carry its free end with the pointer (issue #359).
  ///
  /// The slop is what keeps a *click* near an endpoint from being destructive:
  /// until it is cleared the cable is still wired, and the release reads as the
  /// click that selects it.
  void _moveCableGrab(Offset scene) {
    if (_controller.reroutingCable == null) {
      if ((scene - _pressCableScene).distance < _clickSlop) return;
      _controller.beginCableReroute(_pressCable!, anchor: _pressCableAnchor!);
      _setHover(SystemMouseCursors.precise, null);
    }
    setState(() => _cursor = scene);
  }

  /// Start (on the first move past [_clickSlop]) and then advance the node
  /// drag. Deltas are measured in **scene** space against the last applied
  /// point — which starts at the press point — so the slop distance is carried
  /// into the first step instead of being discarded, and the zoom scale is
  /// already divided out. The node therefore sits under the pointer at any zoom.
  void _moveNodeDrag(Offset scene) {
    if (!_draggingNode) {
      if ((scene - _nodePressScene).distance < _clickSlop) return;
      _draggingNode = true;
      _controller.beginNodeDrag(_pressNode!);
    }
    _controller.dragSelectedBy(scene - _nodeDragScene);
    _nodeDragScene = scene;
  }

  void _onPointerUp(PointerUpEvent event) {
    // Take keyboard focus on release — *after* the enclosing pane's own
    // pointer-down focus grab, so the canvas keeps focus for Delete / Ctrl+D /
    // Ctrl+Z once a gesture completes (mirrors the piano roll's focus-on-gesture).
    // Never on a press that landed on a self-driven body: the `.i`/`.f` field
    // underneath has just taken focus to place its caret, and taking it back
    // here is precisely what made number boxes uneditable (issue #353).
    final onBody = _pressOnInteractiveBody;
    _pressOnInteractiveBody = false;
    if (!onBody) _focus.requestFocus();
    if (_panning) {
      // A pan is a gesture in its own right, and it moves the scene under the
      // cursor — so the click before it can no longer be half of anything.
      _invalidatePendingTap();
      _panning = false;
      _spacePan = false;
      // The scene moved under a stationary pointer, so what it is over is a
      // different question now than it was at the press.
      _hoverLocal = event.localPosition;
      _spaceStillHeld() ? _showSpaceCursor() : _applyHover(event.localPosition);
      return;
    }
    final scene = _toScene(event.localPosition);

    // A cable-end press that never cleared the slop is not a re-route: it is
    // the click that selects the cable it landed on (issue #359).
    final grabbed = _pressCable;
    _pressCable = null;
    _pressCableAnchor = null;
    if (grabbed != null && _controller.reroutingCable == null) {
      _invalidatePendingTap();
      _controller.selectCable(grabbed);
      return;
    }

    // Finish an in-flight cable drag — a fresh one from either end, or the
    // free end of a cable detached for re-routing.
    final anchor = _controller.graph.dragSourcePort;
    if (anchor != null) {
      _invalidatePendingTap();
      _finishCableDrag(anchor, scene);
      _applyHover(event.localPosition);
      return;
    }

    if (_pressNode != null) {
      _endNodePress(event.timeStamp);
      return;
    }

    final press = _pressScene;
    _pressScene = null;
    if (press == null) return;

    if (_movedSincePress) {
      // A press that moved is a marquee, not a click — and, exactly as on a
      // node (issue #352), it invalidates the press before it, so
      // click → marquee → click can never pair into a create.
      _invalidatePendingTap();
      if (_marquee != null) {
        _applyMarquee(_marquee!, additive: _marqueeAdditive);
        setState(() => _marquee = null);
      }
      return;
    }
    // A click on empty canvas: pick a cable, or clear the selection — and pair
    // two movement-free clicks on the *grid* into the inline object box.
    final cable = _cableAt(press);
    if (cable != null) {
      // A cable is a thing, not empty canvas: clicking one is its own gesture
      // and never half of a create.
      _invalidatePendingTap();
      _controller.selectCable(cable);
      return;
    }
    _controller.clearSelection();
    _pairEmptyTap(event.localPosition, press, event.timeStamp);
  }

  /// Release of a cable drag anchored at [anchor] (issue #359).
  ///
  /// One path for all four outcomes, because they differ only in what is
  /// journaled: a *fresh* drag connects or rejects, a *re-route* moves the
  /// cable it detached, deletes it when the drop found no port, or is refused
  /// and leaves it where it was. Whichever end is anchored, the connect is
  /// always expressed outlet → inlet, so nothing downstream has to know the
  /// gesture ran backwards.
  void _finishCableDrag(PatchPortId anchor, Offset scene) {
    final backwards = anchor.side == PatchPortSide.input;
    final other = _portAt(
      scene,
      backwards ? PatchPortSide.output : PatchPortSide.input,
      PatchCanvasConstants.portHitRadius,
    );
    final rerouting = _controller.reroutingCable != null;
    if (other == null) {
      // Dropped on nothing. A cable that was never made simply isn't; a
      // detached one is thrown away for good — journaled, so Ctrl+Z re-wires it.
      if (rerouting) _controller.dropReroutedCable();
      _controller.endCableDrag();
      return;
    }
    final source = backwards ? other : anchor;
    final target = backwards ? anchor : other;
    final connected = rerouting
        ? _controller.rerouteViaGesture(source, target)
        : _controller.connectViaGesture(source, target);
    if (!connected) _flashReject();
    _controller.endCableDrag();
  }

  /// The empty-canvas half of the double-click pairing (issue #358): a second
  /// movement-free click near the first, inside the platform's double-tap
  /// window, opens the inline object box at that scene point.
  ///
  /// Deliberately the *same* mechanism as the node pairing above rather than a
  /// second one: a `GestureDetector.onDoubleTap` here would sit in the arena
  /// against the marquee and the node drags this canvas already owns, which is
  /// exactly the competition issue #352 removed.
  void _pairEmptyTap(Offset local, Offset scene, Duration at) {
    final paired =
        _lastTapOnEmpty &&
        at - _lastTapAt <= kDoubleTapTimeout &&
        (local - _lastTapLocal).distance <= kDoubleTapSlop;
    _invalidatePendingTap();
    if (paired) {
      _openInlineCreate(scene);
      return;
    }
    _lastTapOnEmpty = true;
    _lastTapLocal = local;
    _lastTapAt = at;
  }

  /// Forget the press that was waiting to become the first half of a
  /// double-click — because it was completed, or because something happened
  /// that is not half of anything (a drag, a right-click, a cancel).
  void _invalidatePendingTap() {
    _lastTapNode = null;
    _lastTapOnEmpty = false;
    _lastTapLocal = Offset.zero;
    _lastTapAt = Duration.zero;
  }

  // ─── inline object creation (issue #358) ──────────────────────────────

  void _openInlineCreate(Offset scene) {
    if (widget.objectTypes.isEmpty || widget.onCreateObject == null) return;
    setState(() => _inlineCreateAt = scene);
  }

  /// Take the box down and hand the keyboard back to the canvas, so `Ctrl+Z`
  /// reaches the undo scope straight away — the object just typed is undone
  /// without a click in between, which is the whole point of a keyboard path.
  void _closeInlineCreate() {
    setState(() => _inlineCreateAt = null);
    _focus.requestFocus();
  }

  /// The box resolved a type and its arguments passed the check: report it at
  /// the scene point the box was opened on, then close.
  void _createInline(PatchObjectDescriptor desc, String args) {
    final at = _inlineCreateAt;
    if (at != null) widget.onCreateObject?.call(desc, at, args: args);
    _closeInlineCreate();
  }

  /// Whether a press at [global] landed inside the open box's own rectangle.
  /// Measured against the rendered box rather than a guessed rect: the box
  /// grows and shrinks with its completion list, so nothing else knows its size.
  bool _pressInsideInlineBox(Offset global) {
    final render =
        _inlineBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (render == null || !render.hasSize) return false;
    return (Offset.zero & render.size).contains(render.globalToLocal(global));
  }

  /// Release over a node: commit the drag, or — when the press never cleared
  /// the slop — treat it as the tap that selects, and pair it with a previous
  /// movement-free press to detect a double-click.
  void _endNodePress(Duration at) {
    final id = _pressNode!;
    _pressNode = null;
    if (_draggingNode) {
      _draggingNode = false;
      // A press that moved is never half of a double-click — and it invalidates
      // the press before it, so click-select → drag → click can't pair either.
      _invalidatePendingTap();
      _controller.endNodeDrag(snapToGrid: widget.snapToGrid);
      return;
    }
    final node = _controller.graph.nodeById(id);
    if (node == null) return;
    _onNodeTap(node);
    final paired = _lastTapNode == id && at - _lastTapAt <= kDoubleTapTimeout;
    _invalidatePendingTap();
    if (paired) {
      widget.onNodeDoubleTap?.call(node);
    } else {
      _lastTapNode = id;
      _lastTapAt = at;
    }
  }

  /// A right-click over a node: make it the thing the menu's verbs act on, then
  /// hand it to the surface to open the menu at [global] (issue #356).
  ///
  /// A right-click on a node that is *not* in the current selection selects it
  /// alone, so `duplicate` / `delete` can never act on something the user isn't
  /// pointing at; a right-click *inside* a multi-selection leaves that selection
  /// intact, so the menu operates on the whole group. Either way the reference
  /// panel follows, exactly as a left-click's would. A press on empty canvas
  /// opens nothing — the canvas has no verbs of its own yet.
  void _onSecondaryPress(Offset global, Offset scene) {
    final open = widget.onNodeContextMenu;
    if (open == null) return;
    final node = _nodeAt(scene);
    if (node == null) return;
    _focus.requestFocus();
    // A right-click is its own gesture, so it invalidates any pending left-click
    // pairing exactly as a moved press does — otherwise the click before it and
    // the click after it pair up and the params dialog opens off a double-click
    // the user never made.
    _invalidatePendingTap();
    if (!_controller.graph.isNodeSelected(node.id)) {
      _controller.selectNode(node.id);
    }
    widget.onNodeTap?.call(node);
    open(node, global);
  }

  /// A pointer torn away mid-gesture never delivers the pointer-up the gesture
  /// was waiting for — the window loses capture, a dialog opens over the press,
  /// a system drag or another recogniser claims the pointer. Everything the
  /// gesture armed is dropped here, so nothing survives it (issue #355).
  void _onPointerCancel(PointerCancelEvent event) => _resetGesture();

  /// Drop **every** transient this canvas and its controller accumulate during
  /// a gesture, returning both to the idle state.
  ///
  /// Deliberately one path rather than a clear beside each gesture's own end:
  /// a field that a new gesture adds but a cancel forgets is invisible until it
  /// sticks — a marquee rectangle left painted over the scene, a ghost cable
  /// glued to the cursor, `graph.dragSourcePort` still set so *every* later
  /// press is swallowed, `_panning` still true so the next release is read as
  /// the end of a pan. Add new gesture state here as well as where it is set.
  void _resetGesture() {
    // A cancelled drag is not an edit: the nodes go back where the press found
    // them and nothing is journaled. Unconditional — the point of this path is
    // that it clears drag origins however they got there.
    _controller.abortNodeDrag();
    // A cancelled re-route puts its cable back. Ordered before the drag is
    // dropped because a cable that quietly vanished — the window lost capture
    // mid-gesture — is the worst thing this path could leave behind (#359).
    _controller.abortCableReroute();
    // Drop the in-flight cable and its ghost. A stuck source port is the worst
    // of these: `_onPointerDown` bails out while one is set, so the canvas goes
    // inert until a click happens to clear it.
    _controller.endCableDrag();
    setState(() {
      _panning = false;
      // The *pointer* half of a space pan goes with it. `_spaceHeld` is
      // deliberately left alone: it mirrors a key that is still physically
      // down, and a cancelled pointer does not lift it — clearing it here would
      // leave the mode disarmed under a held space, with no key-up left to put
      // it right. Its own release path (key-up, focus loss) still ends it.
      _spacePan = false;
      // An open nudge burst is dropped with everything else: `abortNodeDrag`
      // above has already put its nodes back, so leaving the flag set would
      // have the next arrow key add to origins that no longer exist. In
      // practice unreachable — a press commits the burst before any gesture
      // that could be cancelled starts — but this path exists precisely so no
      // transient depends on being reached the way it was expected to (#355).
      _nudging = false;
      _pressOnInteractiveBody = false;
      _pressCable = null;
      _pressCableAnchor = null;
      _pressCableScene = Offset.zero;
      _hoverCursor = SystemMouseCursors.basic;
      _hoverPort = null;
      _pressNode = null;
      _nodePressScene = Offset.zero;
      _nodeDragScene = Offset.zero;
      _draggingNode = false;
      // A press the user never completed is never half of a double-click — and
      // it invalidates the press before it, exactly as a moved press does.
      //
      // An *open* inline object box is deliberately not dropped here: it is the
      // result of a completed gesture, not part of one in flight — the same
      // standing the params dialog a node double-click opened has — and a
      // cancelled press must not throw away a name half typed into it.
      _invalidatePendingTap();
      _pressScene = null;
      _marqueeAnchor = null;
      _marqueeAdditive = false;
      _movedSincePress = false;
      _marquee = null;
    });
  }

  /// Selection side of a movement-free press on a node. Focus was already taken
  /// by [_onPointerUp] — the one place that decides whether this gesture may
  /// claim it at all.
  void _onNodeTap(PatchNode node) {
    _controller.selectNode(
      node.id,
      additive: HardwareKeyboard.instance.isShiftPressed,
    );
    widget.onNodeTap?.call(node);
  }

  /// Keep the ghost cable's head on the pointer. Only meaningful while a cable
  /// drag is in flight, and deliberately silent otherwise — this runs on every
  /// pointer move, and the scene must not rebuild for a pointer that is merely
  /// passing through.
  void _trackGhost(Offset local) {
    if (_controller.graph.dragSourcePort == null) return;
    setState(() => _cursor = _toScene(local));
  }

  // ─── hover affordances (issue #359) ─────────────────────────────────────

  void _onPointerHover(PointerHoverEvent event) {
    _trackGhost(event.localPosition);
    _applyHover(event.localPosition);
  }

  /// Work out what the pointer is over and say so — a cursor, and a ring on a
  /// hovered port.
  ///
  /// Resolved against the *same* hit-tests [_onPointerDown] uses and in the
  /// same order, so the cursor is a truthful preview of what a press would do
  /// rather than a second, drifting opinion about where things are.
  void _applyHover(Offset local) {
    _hoverLocal = local;
    // Space held is a mode: it overrides every hit-test below, exactly as the
    // press does, so the hand the cursor shows is a truthful promise that this
    // press will pan (issue #369).
    if (_spaceStillHeld()) {
      _showSpaceCursor();
      return;
    }
    if (_controller.graph.dragSourcePort != null) {
      // Mid-drag the pointer means one thing only: where this cable will land.
      _setHover(SystemMouseCursors.precise, null);
      return;
    }
    final scene = _toScene(local);
    final port = _portPressAt(scene);
    if (port != null) {
      _setHover(SystemMouseCursors.precise, port);
      return;
    }
    if (_cableEndAt(scene) != null) {
      _setHover(SystemMouseCursors.grab, null);
      return;
    }
    final node = _nodeAt(scene);
    if (node != null) {
      // A body that runs its own gestures is not draggable from here, and sets
      // whatever cursor it wants from deeper in the tree.
      _setHover(
        _onInteractiveBody(node, scene)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.move,
        null,
      );
      return;
    }
    _setHover(
      _cableAt(scene) != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      null,
    );
  }

  /// Commit a hover result, rebuilding **only** when it actually changed. The
  /// guard is the whole economy of the feature: a pointer crossing empty canvas
  /// reports dozens of times a second and must cost nothing.
  void _setHover(MouseCursor cursor, PatchPortId? port) {
    if (cursor == _hoverCursor && port == _hoverPort) return;
    setState(() {
      _hoverCursor = cursor;
      _hoverPort = port;
    });
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

  /// The ports a drop would be accepted on, for a drag anchored at [anchor].
  ///
  /// A forward drag (from an outlet) lights up compatible **inlets**; a
  /// backwards one (from an inlet, issue #359) lights up compatible
  /// **outlets**. Either way the question asked is the same
  /// [PatcherController.canConnect] the release will ask, so a highlighted port
  /// can never reject the drop it invited.
  List<PatchPortId> _compatiblePorts(PatchPortId anchor) {
    final backwards = anchor.side == PatchPortSide.input;
    final side = backwards ? PatchPortSide.output : PatchPortSide.input;
    final out = <PatchPortId>[];
    for (final n in _controller.graph.nodes) {
      final count = backwards ? n.outputs.length : n.inputs.length;
      for (var i = 0; i < count; i++) {
        final id = PatchPortId(nodeId: n.id, side: side, index: i);
        final ok = backwards
            ? _controller.canConnect(id, anchor)
            : _controller.canConnect(anchor, id);
        if (ok) out.add(id);
      }
    }
    return out;
  }

  // ─── hit-testing (scene coordinates) ─────────────────────────────────────

  /// The node under [scene], topmost first: nodes paint in graph order, so a
  /// press on an overlap belongs to the last one drawn — the one the user sees.
  PatchNode? _nodeAt(Offset scene) {
    for (final n in _controller.graph.nodes.toList().reversed) {
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

  /// Whether [scene] lands on a node body that runs its own gestures (fader,
  /// number field, message box). Measured against the node's exact body rect —
  /// [_nodeAt]'s halo and the header stay draggable.
  ///
  /// The single notion of "the widget owns this press": it decides both that no
  /// node drag starts here (issue #352) and that the canvas leaves keyboard
  /// focus alone on release (issue #353).
  bool _onInteractiveBody(PatchNode node, Offset scene) {
    if (NodeTypeRegistry.instance.find(node.type)?.interactiveBody != true) {
      return false;
    }
    return Rect.fromLTWH(
      node.position.dx,
      node.position.dy + PatchCanvasConstants.headerHeight,
      node.size.width,
      node.size.height - PatchCanvasConstants.headerHeight,
    ).contains(scene);
  }

  /// Every port centre in the scene, rebuilt only when the graph reports a
  /// change.
  ///
  /// Hit-testing used to run on presses alone; hover (issue #359) runs it on
  /// every pointer report, and rebuilding a map per node per event is exactly
  /// the churn a 120 Hz pointer turns into garbage. `graph.version` bumps on
  /// node moves too — the graph re-broadcasts them — so the cache can never
  /// hand out a stale position.
  int _positionsVersion = -1;
  Map<PatchPortId, Offset> _positionsCache = const {};
  Map<PatchPortId, Offset> get _portPositions {
    final graph = _controller.graph;
    if (graph.version != _positionsVersion) {
      final out = <PatchPortId, Offset>{};
      for (final n in graph.nodes) {
        out.addAll(portPositionsFor(n));
      }
      _positionsCache = out;
      _positionsVersion = graph.version;
    }
    return _positionsCache;
  }

  /// The port under a **press**, either side. Tight, so a press on the header
  /// or the body reaches the node underneath instead of starting a stray cable
  /// (issue #352); both sides, so a cable can be started backwards from an
  /// inlet (issue #359).
  PatchPortId? _portPressAt(Offset scene) =>
      _portAt(scene, null, PatchCanvasConstants.portPressRadius);

  /// The nearest port to [scene] within [hitR], restricted to [side] when one
  /// is given. Nearest rather than first-found: two nodes may overlap, and the
  /// dot the user is actually pointing at is the one that should answer.
  PatchPortId? _portAt(Offset scene, PatchPortSide? side, double hitR) {
    PatchPortId? best;
    var bestDistance = hitR;
    for (final entry in _portPositions.entries) {
      if (side != null && entry.key.side != side) continue;
      final d = (entry.value - scene).distance;
      if (d <= bestDistance) {
        bestDistance = d;
        best = entry.key;
      }
    }
    return best;
  }

  /// The cable whose **endpoint** a press at [scene] landed beside, paired with
  /// the end that would stay put (issue #359).
  ///
  /// Two conditions, both necessary: the press is on the wire
  /// ([PatchCanvasConstants.cableHitThreshold]) *and* within
  /// [PatchCanvasConstants.cableGrabRadius] of one of its ends. A press further
  /// along the cable is therefore still the click that selects it, and the dot
  /// itself has already been claimed by [_portPressAt] for starting a new one.
  _CableGrab? _cableEndAt(Offset scene) {
    final cable = _cableAt(scene);
    if (cable == null) return null;
    final positions = _portPositions;
    final a = positions[cable.source];
    final b = positions[cable.target];
    if (a == null || b == null) return null;
    final atSource = (a - scene).distance;
    final atTarget = (b - scene).distance;
    const reach = PatchCanvasConstants.cableGrabRadius;
    if (atSource > reach && atTarget > reach) return null;
    // Grabbing the outlet end anchors the inlet, and the other way round.
    return atSource <= atTarget
        ? _CableGrab(cable: cable, anchor: cable.target)
        : _CableGrab(cable: cable, anchor: cable.source);
  }

  PatchCable? _cableAt(Offset scene) {
    final positions = _portPositions;
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

  /// Audio or control, for the port a drag is anchored at — the ghost is solid
  /// for one and dashed for the other. Reads whichever side [anchor] is on, so
  /// a backwards drag is drawn as truthfully as a forward one (issue #359).
  PatchPortKind _kindForAnchor(PatchPortId anchor) {
    final node = _controller.graph.nodeById(anchor.nodeId);
    if (node == null) return PatchPortKind.control;
    final ports = anchor.side == PatchPortSide.output
        ? node.outputs
        : node.inputs;
    if (anchor.index >= ports.length) return PatchPortKind.control;
    return ports[anchor.index].kind;
  }

  /// The data type the in-flight ghost is coloured by.
  ///
  /// A forward drag knows its outlet's `OutType` exactly. A backwards one
  /// (issue #359) has only the inlet it started from and no outlet yet, so it
  /// colours by what that inlet *accepts* — audio if it takes a buffer, control
  /// otherwise — which is the same distinction the finished cable will show.
  PatchOutletType _ghostTypeFor(PatchPortId anchor) {
    if (anchor.side == PatchPortSide.output) {
      return _controller.outletTypeOf(anchor);
    }
    return _controller.inletAcceptsOf(anchor).contains(PatchInletAccept.buffer)
        ? PatchOutletType.buffer
        : PatchOutletType.float;
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
    final clamped = (scale * factor).clamp(_minScale, _maxScale);
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

/// A cable caught near one of its endpoints, with the end that stays put.
class _CableGrab {
  const _CableGrab({required this.cable, required this.anchor});

  final PatchCable cable;

  /// The endpoint the gesture leaves alone — the far end from the grab, and the
  /// port the ghost cable hangs off while the free end follows the pointer.
  final PatchPortId anchor;
}

/// A ring drawn on a compatible port while a cable is being dragged — inlets
/// for a forward drag, outlets for a backwards one (issue #359).
class _PortHighlight extends StatelessWidget {
  const _PortHighlight();

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

/// A quiet ring on the port under the pointer (issue #359).
///
/// Deliberately dimmer than [_PortHighlight]: this one only says "there is a
/// target here", while that one says "let go and it will connect".
class _PortHoverRing extends StatelessWidget {
  const _PortHoverRing();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: PhiColors.fg1.withValues(alpha: 0.7),
          width: 1,
        ),
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
