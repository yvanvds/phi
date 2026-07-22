import 'package:flutter/material.dart';

import '../../design/tokens/phi_colors.dart';
import '../../design/tokens/phi_type.dart';
import '../../design/widgets/dialog/delete_impact_dialog.dart';
import '../../design/widgets/patcher/patch_grid_painter.dart';
import '../../design/widgets/state_machine/state_canvas_constants.dart';
import '../../domain/project/entity_address.dart';
import '../../domain/session/session_state.dart';
import '../../domain/state_machine/state_transition.dart';
import '../../engine/state/state_entity_selection.dart';
import '../../engine/state/state_machine_controller.dart';
import 'state_ghost_transition.dart';
import 'state_node_view.dart';
import 'state_transition_layer.dart';

/// The state-graph pan/zoom canvas, rendered from the registry through the
/// [StateMachineController] (issue #241). Hosts the grid backdrop (reused
/// from the patcher — same scope-backdrop intent), the transition layer,
/// every state node, and the in-flight ghost transition. Tracks the
/// cursor's canvas-local position so the ghost can follow it.
///
/// Standard affordances ride context menus: a secondary tap on empty
/// canvas offers *new state* at that spot; a secondary tap on a node
/// offers *duplicate* and *delete* (the latter behind the delete-impact
/// dialog when other entities still point at the state).
class StateCanvas extends StatefulWidget {
  const StateCanvas({
    required this.controller,
    required this.session,
    super.key,
  });

  final StateMachineController controller;
  final SessionState session;

  @override
  State<StateCanvas> createState() => _StateCanvasState();
}

class _StateCanvasState extends State<StateCanvas> {
  Offset _cursor = Offset.zero;

  StateMachineController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Listener(
      onPointerMove: (e) => _updateCursor(e.localPosition),
      onPointerHover: (e) => _updateCursor(e.localPosition),
      onPointerUp: (e) => _onPointerUp(e.localPosition),
      child: InteractiveViewer(
        transformationController: controller.transform,
        constrained: false,
        minScale: 0.25,
        maxScale: 4.0,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        child: SizedBox(
          width: StateCanvasConstants.canvasSize,
          height: StateCanvasConstants.canvasSize,
          child: ListenableBuilder(
            // Rebuild on controller changes (the registry view, arms, the
            // live state, drags) *and* on selection changes — selection
            // drives the outer ring on whichever node carries it.
            listenable: Listenable.merge([
              controller,
              widget.session.selection,
            ]),
            builder: (context, _) {
              final nodes = controller.states;
              final selection = widget.session.selection.value;
              final selectedAddress =
                  selection is StateEntitySelection &&
                      identical(selection.controller, controller)
                  ? selection.address
                  : null;
              final rects = <EntityAddress, Rect>{
                for (final n in nodes) n.address: rectFor(n),
              };
              final transitions = controller.transitions;
              // Index armed transitions by target node so each node can
              // look up its capsule label in O(1). At most one armed
              // capsule per node — duplicates are unlikely in practice
              // and the first wins.
              final armedByTarget = <EntityAddress, StateTransition>{};
              for (final t in transitions) {
                if (t.armed) {
                  armedByTarget.putIfAbsent(t.target, () => t);
                }
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: PatchGridPainter()),
                    ),
                  ),
                  Positioned.fill(
                    child: StateTransitionLayer(
                      transitions: transitions,
                      nodeRects: rects,
                      version: controller.version,
                      onTransitionTap: controller.toggleArmed,
                    ),
                  ),
                  // Above the transition layer (whose paint hit-tests the
                  // whole canvas) but below the nodes: translucent, and it
                  // claims only secondary taps — primary pointers still
                  // reach the transition layer and the pan/zoom.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onSecondaryTapDown: (d) => _onCanvasContextMenu(
                        d.globalPosition,
                        d.localPosition,
                      ),
                    ),
                  ),
                  for (final n in nodes)
                    Positioned(
                      left: n.position.dx,
                      top: n.position.dy,
                      width: StateCanvasConstants.nodeWidth,
                      height: StateCanvasConstants.nodeHeight,
                      child: StateNodeView(
                        node: n,
                        controller: controller,
                        onPinDown: _onPinDown,
                        onSelect: () => _select(n.address),
                        onContextMenu: (global) =>
                            _onNodeContextMenu(n.address, global),
                        isLive: controller.activeStateAddress == n.address,
                        armedTransition: armedByTarget[n.address],
                        selected: selectedAddress == n.address,
                      ),
                    ),
                  if (controller.dragSourceState != null)
                    Positioned.fill(
                      child: StateGhostTransition(
                        source:
                            rects[controller.dragSourceState!]?.center ??
                            Offset.zero,
                        cursor: _cursor,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _select(EntityAddress address) {
    widget.session.select(
      StateEntitySelection(controller: _controller, address: address),
    );
  }

  void _updateCursor(Offset local) {
    if (_controller.dragSourceState == null) return;
    setState(() => _cursor = local);
  }

  void _onPinDown(EntityAddress from, Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ?? global;
    setState(() => _cursor = local);
    _controller.beginTransitionDrag(from);
  }

  void _onPointerUp(Offset local) {
    final source = _controller.dragSourceState;
    if (source == null) return;
    final hit = _findStateAt(local);
    if (hit != null && hit != source) {
      _controller.connect(source, hit);
    }
    _controller.endTransitionDrag();
  }

  EntityAddress? _findStateAt(Offset local) {
    const pad = StateCanvasConstants.nodeHitPadding;
    for (final n in _controller.states) {
      final r = rectFor(n).inflate(pad);
      if (r.contains(local)) return n.address;
    }
    return null;
  }

  // ─── context menus (standard affordances, issue #241) ───────────────────

  Future<void> _onCanvasContextMenu(Offset global, Offset canvasLocal) async {
    final choice = await _showMenu(global, const [('new state', 'new')]);
    if (choice != 'new' || !mounted) return;
    final address = _controller.addState(position: canvasLocal);
    _select(address);
  }

  Future<void> _onNodeContextMenu(EntityAddress address, Offset global) async {
    final choice = await _showMenu(global, const [
      ('duplicate', 'duplicate'),
      ('delete', 'delete'),
    ]);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'duplicate':
        final copy = _controller.duplicateState(address);
        if (copy != null) _select(copy);
      case 'delete':
        await _deleteWithImpact(address);
    }
  }

  /// Delete the state at [address], raising the delete-impact dialog first
  /// when other entities (inbound transitions, MIDI-graph guards) still
  /// point at it.
  Future<void> _deleteWithImpact(EntityAddress address) async {
    final impact = _controller.impactOf(address);
    if (impact.hasReferrers) {
      final confirmed = await DeleteImpactDialog.show(
        context,
        title: 'delete ${address.name}?',
        message:
            'These still point at ${address.format()}. '
            'Deleting it strands them:',
        referrers: [for (final r in impact.referrers) r.format()],
      );
      if (!confirmed || !mounted) return;
    }
    final selection = widget.session.selection.value;
    if (selection is StateEntitySelection && selection.address == address) {
      widget.session.clearSelection();
    }
    _controller.removeState(address);
  }

  Future<String?> _showMenu(Offset global, List<(String, String)> items) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(global, global),
      Offset.zero & overlay.size,
    );
    return showMenu<String>(
      context: context,
      position: position,
      color: PhiColors.bg2,
      items: [
        for (final (label, value) in items)
          PopupMenuItem<String>(
            value: value,
            height: 32,
            child: Text(
              label,
              style: PhiType.monoS().copyWith(
                fontSize: 11,
                color: PhiColors.fg0,
              ),
            ),
          ),
      ],
    );
  }
}
